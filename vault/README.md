# Vault Installation for Tractus-X Umbrella

This directory contains the automated installation script for HashiCorp Vault, which is required for the Tractus-X Umbrella deployment.

## Prerequisites

Before running the vault installation script, ensure you have the following installed and configured:

- **kubectl** - Kubernetes command-line tool
- **helm** - Helm package manager for Kubernetes
- **jq** - Command-line JSON processor
- **openssl** - OpenSSL toolkit
- **Kubernetes cluster** - Running and accessible via kubectl
- **Hosts file entry** - `vault.tx.test` should point to your cluster IP

## Quick Start

1. **Navigate to the install_vault directory:**
   ```bash
   cd install_vault
   ```

2. **Run the installation script:**
   ```bash
   ./install_vault.sh
   ```

The script will automatically:
- Check all prerequisites
- Install HashiCorp Vault using Helm
- Initialize Vault with 5 unseal keys (threshold: 3)
- Unseal Vault using the first 3 keys
- Configure KV secrets engine
- Create secrets for EDC components
- Set up access policies and tokens

## Script Options

The installation script supports several options:

```bash
# Full installation (default)
./install_vault.sh

# Show help
./install_vault.sh --help

# Only verify existing Vault setup
./install_vault.sh --verify

# Only configure Vault (assumes already installed and unsealed)
./install_vault.sh --configure
```

## What the Script Does

### 1. Prerequisites Check
- Verifies kubectl, helm, jq, and openssl are installed
- Checks if kubectl is configured and cluster is accessible

### 2. Vault Installation
- Adds HashiCorp Helm repository
- Creates `vault` namespace
- Installs Vault with production configuration
- Configures ingress for `vault.tx.test`

### 3. Vault Initialization
- Initializes Vault with 5 key shares and 3 threshold
- Saves keys to `vault-keys.json` (keep this secure!)
- Sets proper file permissions (600)

### 4. Vault Unsealing
- Extracts keys from `vault-keys.json`
- Unseals Vault using the first 3 keys
- Verifies Vault is unsealed and ready

### 5. Vault Configuration
- Enables KV secrets engine at `/secret` path
- Generates RSA key pairs and encryption keys for:
  - `edc-dataconsumer-1`
  - `edc-dataconsumer-2`
  - `edc-dataprovider`
- Creates EDC access policy
- Generates EDC access token

### 6. Verification
- Checks Vault status
- Lists available secrets
- Tests connectivity from within cluster

## Important Files

### vault-keys.json
This file contains the Vault initialization keys and root token. **Keep this file secure!**

```json
{
  "keys": [
    "key1...",
    "key2...",
    "key3...",
    "key4...",
    "key5..."
  ],
  "keys_base64": [...],
  "root_token": "hvs.xxx..."
}
```

**Security Notes:**
- Store this file securely
- Backup the keys to a safe location
- Set file permissions to 600
- Never commit this file to version control

## Vault Access

### Web UI
- URL: http://vault.tx.test
- Use the root token from `vault-keys.json`

### Command Line
```bash
# Check Vault status
kubectl exec -n vault deployment/vault -- vault status

# Access Vault CLI
kubectl exec -n vault deployment/vault -- vault login

# List secrets
kubectl exec -n vault deployment/vault -- vault kv list secret/
```

### Port Forward (for local access)
```bash
kubectl port-forward -n vault svc/vault 8200:8200
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=<root_token_from_vault-keys.json>
vault status
```

## EDC Components Integration

The script creates the following secrets for EDC components:

### dataconsumerOne
- Path: `secret/edc-dataconsumer-1`
- Keys: `tokenSignerPrivateKey`, `tokenSignerPublicKey`, `tokenEncryptionAesKey`

### dataconsumerTwo
- Path: `secret/edc-dataconsumer-2`
- Keys: `tokenSignerPrivateKey`, `tokenSignerPublicKey`, `tokenEncryptionAesKey`

### tx-data-provider
- Path: `secret/edc-dataprovider`
- Keys: `tokenSignerPrivateKey`, `tokenSignerPublicKey`, `tokenEncryptionAesKey`

## Troubleshooting

### Vault Not Starting
```bash
# Check Vault pod status
kubectl get pods -n vault

# Check Vault logs
kubectl logs -n vault deployment/vault

# Check Vault status
kubectl exec -n vault deployment/vault -- vault status
```

### Vault Sealed
If Vault becomes sealed, unseal it using the keys:
```bash
# Extract keys from vault-keys.json
KEY1=$(cat vault-keys.json | jq -r '.keys[0]')
KEY2=$(cat vault-keys.json | jq -r '.keys[1]')
KEY3=$(cat vault-keys.json | jq -r '.keys[2]')

# Unseal Vault
kubectl exec -n vault deployment/vault -- vault operator unseal "$KEY1"
kubectl exec -n vault deployment/vault -- vault operator unseal "$KEY2"
kubectl exec -n vault deployment/vault -- vault operator unseal "$KEY3"
```

### Connectivity Issues
```bash
# Test Vault connectivity
kubectl run test-vault --rm -i --tty --image=curlimages/curl -- curl -I http://vault.tx.test:8200/v1/sys/health

# Check ingress
kubectl get ingress -n vault
```

## Cleanup

To uninstall Vault:
```bash
# Uninstall Vault
helm uninstall vault -n vault

# Delete namespace
kubectl delete namespace vault

# Remove vault-keys.json (if no longer needed)
rm vault-keys.json
```

## Security Considerations

1. **Key Management**: Store `vault-keys.json` securely and backup the keys
2. **Access Control**: Use the EDC access token for applications, not the root token
3. **Network Security**: Consider enabling TLS for production use
4. **Audit Logging**: Enable Vault audit logging for compliance
5. **Auto-unseal**: Consider using auto-unseal for production environments

## Next Steps

After successful Vault installation:

1. Verify Vault is accessible at http://vault.tx.test
2. Ensure `vault-keys.json` is secure
3. Proceed with Tractus-X Umbrella deployment
4. Configure EDC components to use the external Vault

## Support

For issues with this installation script:
- Check the troubleshooting section above
- Review Vault logs: `kubectl logs -n vault deployment/vault`
- Refer to [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- Check [Tractus-X Umbrella Documentation](https://github.com/eclipse-tractusx/tractus-x-umbrella) 