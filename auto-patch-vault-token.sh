#!/bin/bash

# Auto-patch Vault Token Script for Tractus-X Umbrella
# This script patches EDC deployments to use Kubernetes secret instead of hardcoded token

set -e

NAMESPACE="${1:-umbrella}"
SECRET_NAME="${2:-vault-edc-token}"
SECRET_KEY="${3:-token}"

echo "=========================================="
echo "Auto-patch Vault Token Script"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Secret: $SECRET_NAME"
echo "Key: $SECRET_KEY"
echo ""

# Function to patch deployment
patch_deployment() {
    local deployment_name=$1
    local env_index=$2
    
    echo "[INFO] Patching deployment: $deployment_name"
    
    # Check if deployment exists
    if ! kubectl get deployment "$deployment_name" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "[WARNING] Deployment $deployment_name not found, skipping..."
        return 0
    fi
    
    # Patch the deployment
    kubectl patch deployment "$deployment_name" -n "$NAMESPACE" --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/env/$env_index\", \"value\": {\"name\": \"EDC_VAULT_HASHICORP_TOKEN\", \"valueFrom\": {\"secretKeyRef\": {\"name\": \"$SECRET_NAME\", \"key\": \"$SECRET_KEY\"}}}}]"
    
    echo "[SUCCESS] Patched $deployment_name"
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local deployment_name=$1
    local max_wait=300  # 5 minutes
    
    echo "[INFO] Waiting for $deployment_name to be ready..."
    
    for i in $(seq 1 $max_wait); do
        if kubectl get deployment "$deployment_name" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
            echo "[SUCCESS] $deployment_name is ready"
            return 0
        fi
        
        if [ $((i % 10)) -eq 0 ]; then
            echo "[INFO] Still waiting for $deployment_name... ($i seconds)"
        fi
        
        sleep 1
    done
    
    echo "[WARNING] Timeout waiting for $deployment_name to be ready"
    return 1
}

# Main execution
echo "[INFO] Starting auto-patch process..."

# Check if secret exists
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "[ERROR] Secret $SECRET_NAME not found in namespace $NAMESPACE"
    echo "[INFO] Please ensure the Vault token secret is created first:"
    echo "  kubectl apply -f install_vault/vault-edc-token-secret.yaml -n $NAMESPACE"
    exit 1
fi

echo "[SUCCESS] Found secret $SECRET_NAME"

# Patch control plane deployment
patch_deployment "tx-data-provider-dataprovider-edc-controlplane" "30"

# Patch dataplane deployment
patch_deployment "tx-data-provider-dataprovider-edc-dataplane" "30"

# Wait for deployments to be ready
echo ""
echo "[INFO] Waiting for deployments to restart and become ready..."

wait_for_deployment "tx-data-provider-dataprovider-edc-controlplane"
wait_for_deployment "tx-data-provider-dataprovider-edc-dataplane"

# Verify the patch
echo ""
echo "[INFO] Verifying patches..."

# Check control plane logs for Vault errors
echo "[INFO] Checking control plane logs for Vault errors..."
if kubectl logs -n "$NAMESPACE" deployment/tx-data-provider-dataprovider-edc-controlplane --tail=20 2>/dev/null | grep -q "Token look up failed with status 403"; then
    echo "[ERROR] Control plane still has Vault token issues"
    exit 1
else
    echo "[SUCCESS] Control plane Vault authentication working"
fi

# Check dataplane logs for Vault errors
echo "[INFO] Checking dataplane logs for Vault errors..."
if kubectl logs -n "$NAMESPACE" deployment/tx-data-provider-dataprovider-edc-dataplane --tail=20 2>/dev/null | grep -q "Token look up failed with status 403"; then
    echo "[ERROR] Dataplane still has Vault token issues"
    exit 1
else
    echo "[SUCCESS] Dataplane Vault authentication working"
fi

echo ""
echo "=========================================="
echo "Auto-patch completed successfully!"
echo "=========================================="
echo ""
echo "Vault token patches applied to:"
echo "  - tx-data-provider-dataprovider-edc-controlplane"
echo "  - tx-data-provider-dataprovider-edc-dataplane"
echo ""
echo "Both deployments are now using the Kubernetes secret:"
echo "  - Secret: $SECRET_NAME"
echo "  - Key: $SECRET_KEY"
echo ""
echo "To verify, check the logs:"
echo "  kubectl logs -n $NAMESPACE deployment/tx-data-provider-dataprovider-edc-controlplane --tail=10"
echo "  kubectl logs -n $NAMESPACE deployment/tx-data-provider-dataprovider-edc-dataplane --tail=10" 