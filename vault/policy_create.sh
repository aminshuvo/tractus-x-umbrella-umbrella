#!/bin/bash

# Create Vault policies and tokens for EDC components
# This script creates the necessary policies and tokens for Tractus-X EDC components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if vault-keys.json exists
if [ ! -f "vault-keys.json" ]; then
    print_error "vault-keys.json not found. Please run the vault installation script first."
    exit 1
fi

# Get root token
ROOT_TOKEN=$(cat vault-keys.json | jq -r '.root_token')
if [ -z "$ROOT_TOKEN" ] || [ "$ROOT_TOKEN" = "null" ]; then
    print_error "Could not extract root token from vault-keys.json"
    exit 1
fi

print_status "Creating Vault policies and tokens for EDC components..."

# Create EDC policy
print_status "Creating EDC policy..."
cat > /tmp/edc-policy.hcl << 'EOF'
path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

kubectl cp /tmp/edc-policy.hcl vault/vault-0:/tmp/edc-policy.hcl
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault policy write edc-policy /tmp/edc-policy.hcl

print_success "Created EDC policy"

# Create token for EDC components
print_status "Creating EDC token..."
EDC_TOKEN_OUTPUT=$(kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault token create -policy=edc-policy -ttl=8760h)
EDC_TOKEN=$(echo "$EDC_TOKEN_OUTPUT" | grep "token " | awk '{print $2}')

if [ -z "$EDC_TOKEN" ]; then
    print_error "Failed to create EDC token"
    exit 1
fi

print_success "Created EDC token"

# Save token to file
echo "$EDC_TOKEN" > edc-token.txt
print_success "Saved EDC token to edc-token.txt"

# Create Kubernetes secret for the token
print_status "Creating Kubernetes secret for EDC token..."
kubectl create secret generic vault-edc-token \
    --from-literal=token="$EDC_TOKEN" \
    --dry-run=client -o yaml > vault-edc-token-secret.yaml

print_success "Created vault-edc-token-secret.yaml"

# Display usage instructions
echo
print_status "Vault Policy and Token Setup Complete!"
echo
print_status "Generated Files:"
echo "  - edc-token.txt: Contains the EDC token"
echo "  - vault-edc-token-secret.yaml: Kubernetes secret manifest"
echo
print_status "To apply the secret to a namespace:"
echo "  kubectl apply -f vault-edc-token-secret.yaml -n <namespace>"
echo
print_status "To use in Helm values:"
echo "  vault:"
echo "    hashicorp:"
echo "      url: http://vault.tx.test"
echo "      tokenSecretName: vault-edc-token"
echo "      tokenSecretKey: token"
echo
print_status "Token Details:"
echo "  - Policy: edc-policy"
echo "  - TTL: 8760h (1 year)"
echo "  - Permissions: Read access to /secret/data/* and /secret/metadata/*"
echo
print_warning "Keep the edc-token.txt file secure. It contains sensitive authentication data." 