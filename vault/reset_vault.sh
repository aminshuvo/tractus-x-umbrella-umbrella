#!/bin/bash

# Tractus-X Vault Reset Script
# This script completely removes and reinstalls HashiCorp Vault

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

print_warning "This script will completely remove Vault and all its data!"
print_warning "This action cannot be undone!"
echo
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Operation cancelled."
    exit 0
fi

print_status "Starting Vault reset process..."

# Remove Helm release
print_status "Removing Vault Helm release..."
helm uninstall vault -n vault || print_warning "Vault Helm release not found or already removed"

# Remove namespace
print_status "Removing vault namespace..."
kubectl delete namespace vault --ignore-not-found=true

# Remove local files
print_status "Removing local Vault files..."
rm -f vault-keys.json edc-token.txt vault-edc-token-secret.yaml

# Wait for namespace to be fully removed
print_status "Waiting for namespace cleanup..."
sleep 10

print_success "Vault reset completed!"
echo
print_status "You can now run ./install_vault.sh to reinstall Vault." 