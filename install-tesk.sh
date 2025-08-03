#!/bin/bash

# TESK Installation Script for Cromwell Environment
# This script installs TESK using Helm with your existing PVC configuration
# Prerequisites: namespace, PV and PVC must be created manually beforehand

set -e

echo "🚀 Installing TESK in cromwell-ns namespace..."

# Verify prerequisites exist
echo "🔍 Verifying prerequisites..."

# Check if namespace exists
if ! kubectl get namespace cromwell-ns >/dev/null 2>&1; then
    echo "❌ Namespace cromwell-ns not found"
    echo "   Please create it manually first: kubectl create namespace cromwell-ns"
    exit 1
else
    echo "✅ Namespace cromwell-ns exists"
fi

# Check if PVC exists
if ! kubectl get pvc pvc-cromwell -n cromwell-ns >/dev/null 2>&1; then
    echo "❌ PVC pvc-cromwell not found in cromwell-ns namespace"
    echo "   Please deploy your PV and PVC manually first:"
    echo "   kubectl apply -f k8s/pv-cromwell.yaml"
    echo "   kubectl apply -f k8s/pvc-cromwell.yaml"
    exit 1
else
    echo "✅ PVC pvc-cromwell found"
fi

# Check if storage class exists
if ! kubectl get storageclass nfs-csi >/dev/null 2>&1; then
    echo "❌ Storage class nfs-csi not found"
    echo "   Please ensure your NFS CSI driver is installed and configured"
    exit 1
else
    echo "✅ Storage class nfs-csi found"
fi

# Install TESK using Helm
echo "📦 Installing TESK Helm chart..."
cd charts/tesk

# Check if TESK is already installed and uninstall it
if helm list -n cromwell-ns | grep -q "tesk-release"; then
    echo "🗑️  Uninstalling existing TESK release..."
    helm uninstall tesk-release -n cromwell-ns
    echo "✅ Previous TESK installation removed"
    echo "⏳ Waiting 10 seconds for cleanup..."
    sleep 10
else
    echo "ℹ️  No existing TESK installation found"
fi

# Install TESK fresh
echo "🚀 Installing TESK..."
helm install tesk-release . \
  -f values.yaml \
  -n cromwell-ns

echo ""
echo "🎉 TESK installation completed!"
echo ""
echo "📋 Next steps:"
echo "1. Check the installation status:"
echo "   kubectl get pods -n cromwell-ns"
echo ""
echo "2. Check the service:"
echo "   kubectl get svc -n cromwell-ns"
echo ""
echo "3. Access TESK API using port-forward (ClusterIP service):"
echo "   kubectl port-forward svc/tesk-api 8080:8080 -n cromwell-ns"
echo "   curl http://localhost:8080/ga4gh/tes/v1/tasks"
echo ""
echo "4. Or access from within the cluster:"
echo "   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n cromwell-ns -- curl http://tesk-api:8080/ga4gh/tes/v1/tasks"
echo ""
echo "📚 For more information, check the TESK documentation in TESK/documentation/"
