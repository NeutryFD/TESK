# TESK Direct PVC Mount Feature

**Current Version**: v1.14.1-bugfix  
**Image**: `neutry/tesk-core-taskmaster:v1.14.1-bugfix`  
**Status**: Production Ready ✅

## Overview

This feature implements **direct PVC mounting** for TESK (Task Execution Service for Kubernetes) when integrated with Cromwell, eliminating the need for file copying between workflow execution and task execution phases. This optimization significantly improves performance and reduces resource usage by allowing both Cromwell and TESK tasks to access the same shared storage directly.

## Problem Solved

### Before: File Copying Approach
- Cromwell creates workflow files in its own storage
- TESK filer jobs copy input files from external sources to task-specific PVCs
- Task containers execute using copied files
- TESK filer jobs copy output files back to external destinations
- Multiple file copy operations cause performance overhead and resource waste

### After: Direct PVC Mount Approach
- Cromwell and TESK share the same PVC (Persistent Volume Claim)
- No file copying between Cromwell and TESK - direct access to shared storage
- TESK tasks mount specific subdirectories from the shared PVC
- Eliminates filer jobs for shared storage scenarios
- Significantly reduced I/O operations and faster execution

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Cromwell      │    │   Shared PVC     │    │   TESK Tasks    │
│                 │    │   (pvc-cromwell) │    │                 │
│ Creates scripts │───►│ /data/SimpleTest/│◄───│ Execute scripts │
│ Manages output  │    │ ├── workflow-1/  │    │ Direct mount    │
│ Direct mount    │    │ ├── workflow-2/  │    │ No file copy    │
└─────────────────┘    │ └── workflow-n/  │    └─────────────────┘
                       └──────────────────┘
```

## Key Components

### 1. Configuration Files

#### `cromwell.conf`
- **Location**: `/data/cromwell.conf`
- **Purpose**: Configures Cromwell to use TESK backend with coordinated paths
- **Key Settings**:
  ```properties
  backend {
    default = TESK
    providers {
      TESK {
        config {
          root = "/data"                    # Cromwell execution root
          dockerRoot = "/data"              # Container path
          endpoint = "http://tesk-api.cromwell-ns.svc.cluster.local:8080/ga4gh/tes/v1/tasks"
        }
      }
    }
  }
  ```

#### `values.yaml` (TESK Helm Chart)
- **Location**: `/root/MOG/cromwell/TESK/charts/tesk/values.yaml`
- **Purpose**: Configures TESK deployment with shared PVC settings
- **Key Settings**:
  ```yaml
  transfer:
    active: true
    wes_base_path: '/data'                # Host path (Cromwell side)
    tes_base_path: '/data'                # Container path (Task side)
    pvc_name: 'pvc-cromwell'              # Shared PVC name
  ```

### 2. Core Implementation

#### `taskmaster.py` - Main Changes
- **Location**: `/root/MOG/cromwell/TESK/source/tesk-core/src/tesk_core/taskmaster.py`
- **Key Features**:
  - **Dynamic Path Extraction**: Automatically extracts mount paths from JSON task definitions
  - **Mount Deduplication**: Prevents duplicate mount conflicts in Kubernetes
  - **Shared PVC Detection**: Uses environment variables to detect shared PVC configuration
  - **SubPath Calculation**: Properly calculates relative paths for PVC mounting

**Critical Functions:**

1. **Dynamic Mount Generation**:
   ```python
   # Extract unique paths dynamically from JSON
   for input_item in task_data.get('inputs', []):
       if 'url' in input_item:
           url_path = os.path.dirname(input_item['url'])
           if url_path and url_path != '/':
               unique_paths.add(url_path)
   ```

2. **Mount Deduplication**:
   ```python
   # Get existing mount paths to avoid duplicates
   existing_mounts = set(mount.get('mountPath', '') for mount in mounts)
   
   for mount_path in unique_paths:
       if mount_path not in existing_mounts:
           # Add new mount
   ```

3. **SubPath Calculation**:
   ```python
   # Calculate subpath by removing base_path prefix for shared PVC
   if path.startswith(base_path + '/'):
       subpath = path[len(base_path + '/'):]
   ```

## Environment Variables

The feature uses these environment variables for coordination:

| Variable | Source | Value | Purpose |
|----------|--------|--------|---------|
| `TRANSFER_PVC_NAME` | TESK values.yaml | `pvc-cromwell` | Shared PVC name |
| `TES_BASE_PATH` | Derived from container base path | `/data` | Base mount path |
| `TESK_API_TASKMASTER_ENVIRONMENT_HOST_BASE_PATH` | TESK deployment | `/data` | Host-side base path |
| `TESK_API_TASKMASTER_ENVIRONMENT_CONTAINER_BASE_PATH` | TESK deployment | `/data` | Container-side base path |

## File Structure

### Directory Layout on Shared PVC
```
/data/
├── cromwell.conf                    # Cromwell configuration
├── simple_test.wdl                  # Workflow definition
├── SimpleTest/                      # Workflow executions
│   └── {workflow-id}/
│       └── call-HelloWorld/
│           └── execution/
│               ├── script           # Generated execution script
│               ├── stdout           # Task output
│               ├── stderr           # Task errors  
│               └── rc               # Return code
└── cromwell_data/                   # Cromwell metadata
```

### Updated Files

1. **`taskmaster.py`** - Core execution logic
   - Added shared PVC detection
   - Implemented dynamic path extraction
   - Added mount deduplication
   - Fixed subPath calculation bug

2. **`values.yaml`** - TESK configuration
   - Added transfer section with shared PVC settings
   - Configured environment variables for path coordination

3. **`cromwell.conf`** - Cromwell backend configuration
   - Set coordinated paths (`/data`)
   - Configured TESK endpoint

4. **Docker Images**:
   - `neutry/tesk-core-taskmaster:v1.14.1-bugfix` - Latest version with job status detection fix
   - `neutry/tesk-core-filer:v1.0.0-root` - Compatible filer image

## Installation and Usage

### Prerequisites
- Kubernetes cluster with shared storage (e.g., NFS)
- Helm 3.x
- Docker registry access for custom TESK images

### Step 1: Create Shared PVC
```bash
# Create PVC for shared storage
kubectl apply -f k8s/pvc-cromwell.yaml
```

### Step 2: Install TESK with Direct Mount Feature
```bash
# Use the installation script
cd /root/MOG/cromwell
./install-tesk.sh
```

### Step 3: Deploy Cromwell with Shared PVC
```bash
# Apply Cromwell configuration with shared PVC mount
kubectl apply -f k8s/c-cromwel.yaml
```

### Step 4: Execute Workflows
```bash
# Run workflow inside Cromwell pod
kubectl exec -it cromwell-pod -n cromwell-ns -- \
  java -Dconfig.file=/data/cromwell.conf \
  -jar /app/cromwell.jar run /data/simple_test.wdl
```

## Example Execution

### Input: Simple Hello World Workflow
```wdl
version 1.0

workflow SimpleTest {
  call HelloWorld
  output {
    String message = HelloWorld.message
  }
}

task HelloWorld {
  command {
    echo "Hello, World!"
  }
  output {
    String message = stdout()
  }
  runtime {
    docker: "ubuntu:latest"
  }
}
```

### Execution Flow:
1. **Cromwell** creates execution directory: `/data/SimpleTest/{workflow-id}/call-HelloWorld/execution/`
2. **Cromwell** generates script file: `script`
3. **TESK** receives task with paths pointing to shared storage
4. **Taskmaster** calculates mount: `/data/SimpleTest/.../execution` → `SimpleTest/.../execution`
5. **Task container** mounts shared PVC subdirectory and executes script
6. **Output files** written directly to shared storage

### Output Files:
```bash
/data/SimpleTest/d465f105-6b81-4174-af62-a0802152b9af/call-HelloWorld/execution/
├── script    # Cromwell-generated execution script
├── stdout    # "Hello, World!"
├── stderr    # (empty)
└── rc        # 0 (success)
```

## Benefits

### Performance Improvements
- **Eliminated File Copying**: No filer jobs for shared storage scenarios
- **Reduced I/O Operations**: Direct access to shared storage
- **Faster Startup**: Tasks start immediately without file staging
- **Lower Resource Usage**: No temporary storage for file copying

### Operational Benefits
- **Simplified Debugging**: All files accessible in one location
- **Better Monitoring**: Centralized storage for all workflow artifacts
- **Easier Cleanup**: Single storage location for all workflow data
- **Cost Optimization**: Reduced storage and compute requirements

## Troubleshooting

### Common Issues

1. **Mount Path Duplication Error**:
   ```
   Error: mountPath must be unique within the pod
   ```
   **Solution**: The mount deduplication feature resolves this automatically.

2. **Script File Not Found (Exit Code 127)**:
   ```
   Error: /bin/bash: script: No such file or directory
   ```
   **Solution**: Ensure subPath calculation is correct. Check logs for "dir0" issue.

3. **EXECUTOR_ERROR**:
   ```
   Status change from Running to EXECUTOR_ERROR
   ```
   **Solution**: Check task pod logs and verify mount configuration.

### Debugging Commands

```bash
# Check TESK API pod environment
kubectl describe pod tesk-api-xxx -n cromwell-ns | grep -A 20 "Environment:"

# Check task pod mount configuration
kubectl describe pod task-xxx-ex-00-xxx -n cromwell-ns | grep -A 10 "Mounts:"

# Verify shared PVC contents
kubectl exec -it cromwell-pod -n cromwell-ns -- ls -la /data/SimpleTest/

# Check taskmaster logs
kubectl logs task-xxx -n cromwell-ns
```

## Version History

- **v1.14.1-bugfix**: Fixed job status detection bug (handles both Complete and SuccessCriteriaMet conditions)
- **v1.14.0-final**: Complete Direct PVC Mount implementation with optimized taskmaster
- **v1.13.0-path-fixed**: Fixed subPath calculation bug (resolved "dir0" issue)
- **v1.13.0-fixed-staging**: Added error handling and code reviews
- **v1.13.0-dynamic-mounts**: Initial implementation with dynamic mount generation

### Bug Fix Details (v1.14.1-bugfix)

**Issue**: Job status detection was incorrectly reporting 'Error' for successful jobs when Kubernetes returned multiple job conditions.

**Root Cause**: The original code only checked `job.status.conditions[0]` and if it wasn't exactly 'Complete', it defaulted to 'Error'. However, newer Kubernetes versions can return conditions like:
1. `SuccessCriteriaMet: True` (first condition)
2. `Complete: True` (second condition)

**Fix**: Modified `get_status()` method in `job.py` to:
- Check all job conditions, not just the first one
- Accept both `Complete` and `SuccessCriteriaMet` as valid success indicators
- Default to 'Running' instead of 'Error' for ambiguous states

**Impact**: Eliminates false "Cancelling taskmaster: Got status Error" messages when jobs actually succeed.

## Future Enhancements

- Support for multiple shared PVCs
- Automatic cleanup of old workflow directories
- Enhanced monitoring and metrics
- Integration with cloud storage backends
- Support for workflow-level caching

## Contributing

When modifying this feature:

1. **Test Path Calculation**: Ensure subPath is correctly calculated for various path patterns
2. **Verify Mount Deduplication**: Check that duplicate mounts are properly detected
3. **Validate Environment Variables**: Ensure all required environment variables are set
4. **Test Different Storage Classes**: Verify compatibility with various storage backends

## References

- [TESK Documentation](https://github.com/EMBL-EBI-TSI/TESK)
- [Cromwell Documentation](https://cromwell.readthedocs.io/)
- [TES Specification](https://github.com/ga4gh/task-execution-schemas)
- [Kubernetes PVC Documentation](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
