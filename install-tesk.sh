#!/bin/bash

# TESK Installation Script for Cromwell Environment
# This script installs TESK using Helm with your existing PVC configuration
# Prerequisites: namespace, PV and PVC must be created manually beforehand

set -e

echo "🚀 Installing TESK in cromwell namespace..."

# Verify prerequisites exist
echo "🔍 Verifying prerequisites..."

# Check if namespace exists
if ! kubectl get namespace cromwell >/dev/null 2>&1; then
    echo "❌ Namespace cromwell not found"
    echo "   Please create it manually first: kubectl create namespace cromwell"
    exit 1
else
    echo "✅ Namespace cromwell exists"
fi

# Check if PVC exists
if ! kubectl get pvc azurefile-cromwell-pvc -n cromwell >/dev/null 2>&1; then
    echo "❌ PVC azurefile-cromwell-pvc not found in cromwell namespace"
    echo "   Please deploy your PV and PVC manually first:"
    echo "   kubectl apply -f k8s/pv-cromwell.yaml"
    echo "   kubectl apply -f k8s/pvc-cromwell.yaml"
    exit 1
else
    echo "✅ PVC azurefile-cromwell-pvc found"
fi

# Check if storage class exists
if ! kubectl get storageclass azurefile >/dev/null 2>&1; then
    echo "❌ Storage class azurefile not found"
    echo "   Please ensure your Azure File CSI driver is installed and configured"
    exit 1
else
    echo "✅ Storage class azurefile found"
fi

# Install TESK using Helm
echo "📦 Installing TESK Helm chart..."
cd charts/tesk

# Check if TESK is already installed and uninstall it
if helm list -n cromwell | grep -q "tesk-release"; then
    echo "🗑️  Uninstalling existing TESK release..."
    helm uninstall tesk-release -n cromwell
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
  -n cromwell

echo ""
echo "🎉 TESK installation completed!"
echo ""
echo "📋 Next steps:"
echo "1. Check the installation status:"
echo "   kubectl get pods -n cromwell"
echo ""
echo "2. Check the service:"
echo "   kubectl get svc -n cromwell"
echo ""
echo "3. Access TESK API using port-forward (ClusterIP service):"
echo "   kubectl port-forward svc/tesk-api 8080:8080 -n cromwell"
echo "   curl http://localhost:8080/ga4gh/tes/v1/tasks"
echo ""
echo "4. Or access from within the cluster:"
echo "   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n cromwell -- curl http://tesk-api:8080/ga4gh/tes/v1/tasks"
echo ""
echo "📚 For more information, check the TESK documentation in TESK/documentation/"
