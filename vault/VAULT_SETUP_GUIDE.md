# Vault Setup Guide for Tractus-X Umbrella

This guide covers the complete setup and configuration of HashiCorp Vault for use with Tractus-X Umbrella components.

## Overview

HashiCorp Vault is used to securely store and manage secrets for Tractus-X EDC (Eclipse Dataspace Connector) components. This includes:
- Token signing keys (private/public key pairs)
- Token encryption keys
- Access tokens for EDC components

## Quick Start

### 1. Install Vault

```bash
cd install_vault
./install_vault.sh
```

This script will:
- Install Vault via Helm
- Create ingress for external access
- Initialize and unseal Vault
- Configure KV secrets engine
- Create EDC policies and tokens
- Generate Kubernetes secret manifests

### 2. Apply Kubernetes Secret

```bash
# Apply the generated secret to your deployment namespace
kubectl apply -f vault-edc-token-secret.yaml -n umbrella
```

### 3. Update Helm Values

Add the following to your Helm values file:

```yaml
tx-data-provider:
  enabled: true
  tractusx-connector:
    vault:
      hashicorp:
        url: http://vault.tx.test
        tokenSecretName: vault-edc-token
        tokenSecretKey: token
      secretNames:
        transferProxyTokenSignerPrivateKey: tokenSignerPrivateKey
        transferProxyTokenSignerPublicKey: tokenSignerPublicKey
        transferProxyTokenEncryptionAesKey: tokenEncryptionAesKey
```

## Generated Files

After running the installation script, the following files will be created:

### `vault-keys.json`
- **Purpose**: Contains Vault initialization keys and root token
- **Security**: Keep this file secure and backup the keys
- **Location**: `install_vault/vault-keys.json`

### `edc-token.txt`
- **Purpose**: Contains the EDC access token
- **Security**: Contains sensitive authentication data
- **Usage**: Used to create Kubernetes secrets

### `vault-edc-token-secret.yaml`
- **Purpose**: Kubernetes secret manifest for the EDC token
- **Usage**: Apply to deployment namespaces
- **Content**: Base64 encoded token

## Vault Configuration Details

### Policies

The installation creates an `edc-policy` with the following permissions:

```hcl
path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
```

This allows EDC components to:
- Read secret data from any path under `/secret/data/`
- List available secrets
- Access metadata about secrets

### Secrets Structure

Vault stores secrets in the following structure:

```
secret/
├── edc-dataprovider/
│   ├── tokenSignerPrivateKey
│   ├── tokenSignerPublicKey
│   └── tokenEncryptionAesKey
├── edc-dataconsumer-1/
│   ├── tokenSignerPrivateKey
│   ├── tokenSignerPublicKey
│   └── tokenEncryptionAesKey
└── edc-dataconsumer-2/
    ├── tokenSignerPrivateKey
    ├── tokenSignerPublicKey
    └── tokenEncryptionAesKey
```

### Token Configuration

- **Policy**: `edc-policy`
- **TTL**: 8760h (1 year)
- **Renewable**: Yes
- **Access**: Read-only access to secrets

## Manual Operations

### Creating Additional Tokens

```bash
# Get root token
ROOT_TOKEN=$(cat vault-keys.json | jq -r '.root_token')

# Create new token
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault token create -policy=edc-policy -ttl=8760h
```

### Creating Kubernetes Secret

```bash
# Create secret from token
kubectl create secret generic vault-edc-token \
    --from-literal=token="YOUR_TOKEN_HERE" \
    --dry-run=client -o yaml > vault-edc-token-secret.yaml

# Apply to namespace
kubectl apply -f vault-edc-token-secret.yaml -n <namespace>
```

### Adding New Secrets

```bash
# Get root token
ROOT_TOKEN=$(cat vault-keys.json | jq -r '.root_token')

# Add new secret
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault kv put secret/edc-newcomponent \
    tokenSignerPrivateKey="PRIVATE_KEY" \
    tokenSignerPublicKey="PUBLIC_KEY" \
    tokenEncryptionAesKey="ENCRYPTION_KEY"
```

## Troubleshooting

### Vault Authentication Issues

If EDC components show "Token look up failed with status 403":

1. **Check token validity**:
   ```bash
   kubectl exec -n vault vault-0 -- vault token lookup <token>
   ```

2. **Verify policy permissions**:
   ```bash
   kubectl exec -n vault vault-0 -- vault policy read edc-policy
   ```

3. **Check secret access**:
   ```bash
   kubectl exec -n vault vault-0 -- env VAULT_TOKEN=<token> vault kv list secret/
   ```

### Vault Connectivity Issues

1. **Check Vault status**:
   ```bash
   kubectl exec -n vault vault-0 -- vault status
   ```

2. **Test ingress connectivity**:
   ```bash
   curl -I http://vault.tx.test/v1/sys/health
   ```

3. **Verify hosts file entry**:
   ```bash
   grep vault.tx.test /etc/hosts
   ```

### Token Expiration

If tokens expire:

1. **Create new token**:
   ```bash
   cd install_vault
   ./policy_create.sh
   ```

2. **Update Kubernetes secret**:
   ```bash
   kubectl patch secret vault-edc-token -n <namespace> \
       --type='json' -p='[{"op": "replace", "path": "/data/token", "value":"NEW_TOKEN_BASE64"}]'
   ```

3. **Restart EDC pods**:
   ```bash
   kubectl rollout restart deployment -n <namespace> -l app.kubernetes.io/name=edc
   ```

## Security Considerations

### Key Management

- **Backup vault-keys.json**: Store securely and backup the unseal keys
- **Rotate tokens regularly**: Consider token rotation policies
- **Limit token scope**: Use specific policies for different components
- **Monitor access**: Enable Vault audit logging

### Network Security

- **Use HTTPS**: In production, configure TLS for Vault ingress
- **Network policies**: Restrict access to Vault namespace
- **Service mesh**: Consider using Istio for additional security

### Access Control

- **Principle of least privilege**: Grant minimal required permissions
- **Token lifecycle**: Set appropriate TTL for tokens
- **Audit logging**: Monitor Vault access and operations

## Integration with Tractus-X Components

### EDC Components

All EDC components (Data Provider, Data Consumers) use the same Vault configuration:

```yaml
vault:
  hashicorp:
    url: http://vault.tx.test
    tokenSecretName: vault-edc-token
    tokenSecretKey: token
  secretNames:
    transferProxyTokenSignerPrivateKey: tokenSignerPrivateKey
    transferProxyTokenSignerPublicKey: tokenSignerPublicKey
    transferProxyTokenEncryptionAesKey: tokenEncryptionAesKey
```

### Secret Mapping

The `secretNames` configuration maps Vault secret keys to EDC internal names:

- `tokenSignerPrivateKey` → Used for signing transfer tokens
- `tokenSignerPublicKey` → Used for verifying transfer tokens  
- `tokenEncryptionAesKey` → Used for encrypting sensitive data

## Advanced Configuration

### Custom Policies

Create custom policies for specific components:

```hcl
# Component-specific policy
path "secret/data/edc-dataprovider/*" {
  capabilities = ["read"]
}

path "secret/metadata/edc-dataprovider/*" {
  capabilities = ["read"]
}
```

### Token Renewal

Set up automatic token renewal:

```bash
# Create renewable token with shorter TTL
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault token create \
    -policy=edc-policy -ttl=24h -renewable=true
```

### High Availability

For production environments, consider:
- Vault HA deployment with multiple replicas
- Auto-unsealing with cloud KMS
- Integrated storage backend
- Load balancer configuration

## Support

For issues related to:
- **Vault setup**: Check this guide and script logs
- **EDC integration**: Review EDC documentation
- **Kubernetes issues**: Check pod logs and events
- **Network connectivity**: Verify ingress and DNS configuration 