#!/bin/bash

# Tractus-X Vault Installation Script
# This script installs and configures HashiCorp Vault for Tractus-X Umbrella
# Version: 2.12.2

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists kubectl; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    if ! command_exists helm; then
        print_error "helm is not installed. Please install helm first."
        exit 1
    fi
    
    if ! command_exists jq; then
        print_error "jq is not installed. Please install jq first."
        exit 1
    fi
    
    if ! command_exists openssl; then
        print_error "openssl is not installed. Please install openssl first."
        exit 1
    fi
    
    # Check if kubectl is configured
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "kubectl is not configured or cluster is not accessible."
        exit 1
    fi
    
    print_success "All prerequisites are met."
}

# Function to install Vault
install_vault() {
    print_status "Installing HashiCorp Vault..."
    
    # Add HashiCorp Helm repository
    print_status "Adding HashiCorp Helm repository..."
    # helm repo add hashicorp https://helm.releases.hashicorp.com # temporary disabled
    # helm repo update hashicorp # temporary disabled
    
    # Create namespace for vault
    print_status "Creating vault namespace..."
    kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Vault with production configuration
    print_status "Installing Vault with Helm..."
    helm install vault hashicorp/vault \
        --namespace vault \
        --set server.ha.enabled=false \
        --set server.standalone.enabled=true \
        --wait \
        --timeout 10m
    
    print_success "Vault installation completed."
}

# Function to create Vault ingress
create_vault_ingress() {
    print_status "Creating Vault ingress..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: vault
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-credentials: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: vault.tx.test
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vault
            port:
              number: 8200
EOF
    
    print_success "Vault ingress created."
}

# Function to wait for Vault to be running
wait_for_vault() {
    print_status "Waiting for Vault pod to be running..."
    
    # Wait for Vault pod to be running (not ready, since it needs initialization)
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=60s || {
        print_warning "Vault pod is not ready (this is normal - Vault needs initialization)"
        print_status "Checking if Vault pod is running..."
        
        # Wait for pod to be running (not ready)
        for i in {1..30}; do
            if kubectl get pod -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].status.phase}' | grep -q "Running"; then
                print_success "Vault pod is running."
                return 0
            fi
            print_status "Waiting for Vault pod to be running... (attempt $i/30)"
            sleep 10
        done
        
        print_error "Vault pod failed to start"
        exit 1
    }
    
    # Wait a bit more for Vault to fully start
    sleep 10
    
    print_success "Vault pod is running."
}

# Function to initialize Vault
initialize_vault() {
    print_status "Initializing Vault..."
    
    # Wait a bit for Vault to be fully responsive
    sleep 5
    
    # Check if Vault is already initialized
    if kubectl exec -n vault vault-0 -- vault status >/dev/null 2>&1; then
        print_warning "Vault appears to be already initialized. Skipping initialization."
        return 0
    fi
    
    # Initialize Vault
    print_status "Running Vault initialization..."
    kubectl exec -n vault vault-0 -- vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json > vault-keys.json
    
    if [ $? -eq 0 ]; then
        print_success "Vault initialization completed. Keys saved to vault-keys.json"
        print_warning "IMPORTANT: Keep vault-keys.json secure and backup the keys!"
        
        # Set proper permissions on the keys file
        chmod 600 vault-keys.json
    else
        print_error "Vault initialization failed."
        print_status "This might be normal if Vault is still starting up. Retrying in 10 seconds..."
        sleep 10
        
        # Retry initialization
        kubectl exec -n vault vault-0 -- vault operator init \
            -key-shares=5 \
            -key-threshold=3 \
            -format=json > vault-keys.json
        
        if [ $? -eq 0 ]; then
            print_success "Vault initialization completed on retry. Keys saved to vault-keys.json"
            print_warning "IMPORTANT: Keep vault-keys.json secure and backup the keys!"
            chmod 600 vault-keys.json
        else
            print_error "Vault initialization failed after retry."
            exit 1
        fi
    fi
}

# Function to unseal Vault
unseal_vault() {
    print_status "Unsealing Vault..."
    
    # Check if vault-keys.json exists
    if [ ! -f "vault-keys.json" ]; then
        print_error "vault-keys.json not found. Cannot unseal Vault."
        exit 1
    fi
    
    # Extract keys from the JSON file
    KEY1=$(cat vault-keys.json | jq -r '.unseal_keys_b64[0]')
    KEY2=$(cat vault-keys.json | jq -r '.unseal_keys_b64[1]')
    KEY3=$(cat vault-keys.json | jq -r '.unseal_keys_b64[2]')
    ROOT_TOKEN=$(cat vault-keys.json | jq -r '.root_token')
    
    # Unseal Vault using the first 3 keys
    print_status "Unsealing with key 1..."
    kubectl exec -n vault vault-0 -- vault operator unseal "$KEY1"
    
    print_status "Unsealing with key 2..."
    kubectl exec -n vault vault-0 -- vault operator unseal "$KEY2"
    
    print_status "Unsealing with key 3..."
    kubectl exec -n vault vault-0 -- vault operator unseal "$KEY3"
    
    # Verify Vault is unsealed
    print_status "Verifying Vault status..."
    kubectl exec -n vault vault-0 -- vault status
    
    print_success "Vault is unsealed and ready."
}

# Function to configure Vault
configure_vault() {
    print_status "Configuring Vault..."
    
    # Get root token
    if [ ! -f "vault-keys.json" ]; then
        print_error "vault-keys.json not found. Cannot configure Vault."
        exit 1
    fi
    
    ROOT_TOKEN=$(cat vault-keys.json | jq -r '.root_token')
    
    # Enable KV secrets engine
    print_status "Enabling KV secrets engine..."
    kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN && vault secrets enable -path=secret kv-v2"
    
    # Generate secrets for EDC components
    print_status "Creating secrets for EDC components..."
    
    # Generate keys for dataconsumer-1
    DATACONSUMER1_PRIVATE_KEY=$(openssl genrsa 2048 2>/dev/null | base64 -w 0)
    DATACONSUMER1_PUBLIC_KEY=$(echo "$DATACONSUMER1_PRIVATE_KEY" | base64 -d | openssl rsa -pubout 2>/dev/null | base64 -w 0)
    DATACONSUMER1_ENCRYPTION_KEY=$(openssl rand -hex 32)
    
    kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN && vault kv put secret/edc-dataconsumer-1 tokenSignerPrivateKey=\"$DATACONSUMER1_PRIVATE_KEY\" tokenSignerPublicKey=\"$DATACONSUMER1_PUBLIC_KEY\" tokenEncryptionAesKey=\"$DATACONSUMER1_ENCRYPTION_KEY\""
    
    # Generate keys for dataconsumer-2
    DATACONSUMER2_PRIVATE_KEY=$(openssl genrsa 2048 2>/dev/null | base64 -w 0)
    DATACONSUMER2_PUBLIC_KEY=$(echo "$DATACONSUMER2_PRIVATE_KEY" | base64 -d | openssl rsa -pubout 2>/dev/null | base64 -w 0)
    DATACONSUMER2_ENCRYPTION_KEY=$(openssl rand -hex 32)
    
    kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN && vault kv put secret/edc-dataconsumer-2 tokenSignerPrivateKey=\"$DATACONSUMER2_PRIVATE_KEY\" tokenSignerPublicKey=\"$DATACONSUMER2_PUBLIC_KEY\" tokenEncryptionAesKey=\"$DATACONSUMER2_ENCRYPTION_KEY\""
    
    # Generate keys for dataprovider
    DATAPROVIDER_PRIVATE_KEY=$(openssl genrsa 2048 2>/dev/null | base64 -w 0)
    DATAPROVIDER_PUBLIC_KEY=$(echo "$DATAPROVIDER_PRIVATE_KEY" | base64 -d | openssl rsa -pubout 2>/dev/null | base64 -w 0)
    DATAPROVIDER_ENCRYPTION_KEY=$(openssl rand -hex 32)
    
    kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN && vault kv put secret/edc-dataprovider tokenSignerPrivateKey=\"$DATAPROVIDER_PRIVATE_KEY\" tokenSignerPublicKey=\"$DATAPROVIDER_PUBLIC_KEY\" tokenEncryptionAesKey=\"$DATAPROVIDER_ENCRYPTION_KEY\""
    
    # Create edc-wallet-secret for EDC components
    print_status "Creating edc-wallet-secret..."
    kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN && vault kv put secret/edc-wallet-secret content=changeme"
    
    # Create policies and tokens for EDC components
    print_status "Creating EDC policies and tokens..."
    if [ -f "policy_create.sh" ]; then
        chmod +x policy_create.sh
        ./policy_create.sh
    else
        print_warning "policy_create.sh not found. Creating basic EDC policy..."
        # Create basic policy for EDC access
        kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN && vault policy write edc-policy - << 'EOF'
path \"secret/data/*\" {
  capabilities = [\"read\", \"list\"]
}

path \"secret/metadata/*\" {
  capabilities = [\"read\", \"list\"]
}
EOF"
        
        # Create token for EDC components
        print_status "Creating EDC access token..."
        EDC_TOKEN_OUTPUT=$(kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN && vault token create -policy=edc-policy -ttl=8760h")
        EDC_TOKEN=$(echo "$EDC_TOKEN_OUTPUT" | grep "token " | awk '{print $2}')
        
        if [ -n "$EDC_TOKEN" ]; then
            echo "$EDC_TOKEN" > edc-token.txt
            print_success "Saved EDC token to edc-token.txt"
            
            # Create Kubernetes secret manifest
            kubectl create secret generic vault-edc-token \
                --from-literal=token="$EDC_TOKEN" \
                --dry-run=client -o yaml > vault-edc-token-secret.yaml
            
            print_success "Created vault-edc-token-secret.yaml"
            
            # Apply the secret to umbrella namespace
            print_status "Applying vault-edc-token secret to umbrella namespace..."
            kubectl apply -f vault-edc-token-secret.yaml -n umbrella
            print_success "Applied vault-edc-token secret to umbrella namespace"
        fi
    fi
    
    print_success "Vault configuration completed."
}

# Function to verify Vault setup
verify_vault() {
    print_status "Verifying Vault setup..."
    
    # Check Vault status
    print_status "Checking Vault status..."
    kubectl exec -n vault vault-0 -- vault status
    
    # List secrets (if vault-keys.json exists locally)
    if [ -f "vault-keys.json" ]; then
        print_status "Listing available secrets..."
        ROOT_TOKEN=$(cat vault-keys.json | jq -r '.root_token')
        kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN=$ROOT_TOKEN && vault kv list secret/"
    else
        print_warning "vault-keys.json not found locally. Cannot list secrets."
    fi
    
    # Test connectivity from within cluster
    print_status "Testing Vault connectivity from within cluster..."
    kubectl run vault-test --rm -i --tty --image=curlimages/curl -- curl -I http://vault.tx.test/v1/sys/health || print_warning "Vault connectivity test failed"
    
    print_success "Vault verification completed."
}

# Function to display final information
display_info() {
    print_success "Vault installation and configuration completed successfully!"
    echo
    print_status "Important information:"
    echo "  - Vault namespace: vault"
    echo "  - Vault service: vault.vault.svc.cluster.local:8200"
    echo "  - Vault ingress: http://vault.tx.test"
    echo "  - Keys file: vault-keys.json (keep this secure!)"
    echo
    print_status "Generated files:"
    if [ -f "edc-token.txt" ]; then
        echo "  - edc-token.txt: EDC access token"
    fi
    if [ -f "vault-edc-token-secret.yaml" ]; then
        echo "  - vault-edc-token-secret.yaml: Kubernetes secret manifest"
    fi
    echo
    print_warning "Next steps:"
    echo "  1. Ensure vault.tx.test is in your hosts file"
    echo "  2. Keep vault-keys.json secure and backup the keys"
    echo "  3. Apply the Kubernetes secret to your deployment namespace:"
    echo "     kubectl apply -f vault-edc-token-secret.yaml -n <namespace>"
    echo "  4. Update your Helm values to use the token:"
    echo "     vault:"
    echo "       hashicorp:"
    echo "         url: http://vault.tx.test"
    echo "         tokenSecretName: vault-edc-token"
    echo "         tokenSecretKey: token"
    echo "  5. Proceed with Tractus-X Umbrella deployment"
    echo
    print_status "To access Vault UI: http://vault.tx.test"
    print_status "To check Vault status: kubectl exec -n vault vault-0 -- vault status"
}

# Main execution
main() {
    echo "=========================================="
    echo "Tractus-X Vault Installation Script"
    echo "=========================================="
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Install Vault
    install_vault
    
    # Create Vault ingress
    create_vault_ingress
    
    # Wait for Vault to be ready
    wait_for_vault
    
    # Initialize Vault
    initialize_vault
    
    # Unseal Vault
    unseal_vault
    
    # Configure Vault
    configure_vault
    
    # Verify setup
    verify_vault
    
    # Display final information
    display_info
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --verify       Only verify existing Vault setup"
        echo "  --configure    Only configure Vault (assumes already installed and unsealed)"
        echo
        echo "This script installs and configures HashiCorp Vault for Tractus-X Umbrella."
        exit 0
        ;;
    --verify)
        verify_vault
        exit 0
        ;;
    --configure)
        configure_vault
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information."
        exit 1
        ;;
esac 