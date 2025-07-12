# Tractus-X Umbrella Deployment Plan
## Version: 2.12.2


## Overview
This deployment plan covers the installation of Tractus-X Umbrella components with an external Vault setup. The plan includes all requested components and provides step-by-step instructions for a successful deployment.

## Prerequisites
- ✅ Kubernetes cluster (v1.24.x+) already set up
- ✅ Network setup already configured
- ✅ Helm 3.8+ installed
- ✅ kubectl configured and working
- ✅ Minikube with ingress addon enabled (if using Minikube)

## Components to Deploy

### Core Components
1. **portal** - Portal frontend and backend
2. **centralidp** - Central Identity Provider (Keycloak)
3. **sharedidp** - Shared Identity Provider (Keycloak)
4. **bpndiscovery** - BPN Discovery Service
5. **discoveryfinder** - Discovery Finder Service
6. **sdfactory** - Self-Description Factory
7. **managed-identity-wallet** - Managed Identity Wallet
8. **semantic-hub** - Semantic Hub with GraphDB
9. **ssi-credential-issuer** - SSI Credential Issuer
10. **dataconsumerOne** - Data Consumer 1 (EDC + Vault)
11. **tx-data-provider** - Data Provider (EDC + DTR + Vault + Simple Data Backend)
12. **dataconsumerTwo** - Data Consumer 2 (EDC + Vault)
13. **bdrs** - BPN DID Resolution Service (in-memory)
14. **bpdm** - Business Partner Data Management
15. **ssi-dim-wallet-stub** - SSI DIM Wallet Stub

## Vault Setup Plan

### Step 1: Install HashiCorp Vault

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Create namespace for vault
kubectl create namespace vault

# Install Vault with production configuration (not dev mode)
helm install vault hashicorp/vault \
  --namespace vault \
  --set server.ingress.enabled=true \
  --set server.ingress.hosts[0].host=vault.tx.test \
  --set server.ingress.hosts[0].paths[0].path=/ \
  --set server.ingress.hosts[0].paths[0].pathType=Prefix \
  --set server.ingress.ingressClassName=nginx \
  --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/rewrite-target"=/ \
  --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/use-regex"=true \
  --set server.ha.enabled=false \
  --set server.standalone.enabled=true
```

### Step 2: Initialize and Configure Vault

```bash
# Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=300s

# Port forward to access Vault CLI
kubectl port-forward -n vault svc/vault 8200:8200 &

# Set Vault address
export VAULT_ADDR=http://localhost:8200

# Initialize Vault (only needed once)
vault operator init -key-shares=5 -key-threshold=3 -format=json > vault-keys.json

# Save the keys and root token securely
echo "Vault initialization completed. Keys saved to vault-keys.json"
echo "IMPORTANT: Keep vault-keys.json secure and backup the keys!"

# Unseal Vault using the first 3 keys
# Extract keys from the JSON file
KEY1=$(cat vault-keys.json | jq -r '.keys[0]')
KEY2=$(cat vault-keys.json | jq -r '.keys[1]')
KEY3=$(cat vault-keys.json | jq -r '.keys[2]')
ROOT_TOKEN=$(cat vault-keys.json | jq -r '.root_token')

# Unseal Vault
vault operator unseal $KEY1
vault operator unseal $KEY2
vault operator unseal $KEY3

# Verify Vault is unsealed
vault status

# Set the root token
export VAULT_TOKEN=$ROOT_TOKEN

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Create secrets for EDC components
vault kv put secret/edc-dataconsumer-1 tokenSignerPrivateKey="$(openssl genrsa 2048 | base64)" tokenSignerPublicKey="$(openssl rsa -pubout | base64)" tokenEncryptionAesKey="$(openssl rand -hex 32)"
vault kv put secret/edc-dataconsumer-2 tokenSignerPrivateKey="$(openssl genrsa 2048 | base64)" tokenSignerPublicKey="$(openssl rsa -pubout | base64)" tokenEncryptionAesKey="$(openssl rand -hex 32)"
vault kv put secret/edc-dataprovider tokenSignerPrivateKey="$(openssl genrsa 2048 | base64)" tokenSignerPublicKey="$(openssl rsa -pubout | base64)" tokenEncryptionAesKey="$(openssl rand -hex 32)"

# Create policy for EDC access
vault policy write edc-policy - <<EOF
path "secret/data/edc-*" {
  capabilities = ["read"]
}
EOF

# Create token for EDC components
vault token create -policy=edc-policy -ttl=8760h
```

### Step 3: Update DNS/Hosts File
Add the following entry to your hosts file (`/etc/hosts` on Linux/macOS, `C:\Windows\System32\drivers\etc\hosts` on Windows):

```
<MINIKUBE_IP>    vault.tx.test
```

Replace `<MINIKUBE_IP>` with your Minikube IP address.

## Deployment Configuration

### Step 1: Create Custom Values File

Create a file named `custom-values.yaml` with the following configuration:

```yaml
# Enable all required components
portal:
  enabled: true
  replicaCount: 1
  postgresql:
    nameOverride: "portal-backend-postgresql"
    architecture: standalone
    auth:
      password: "dbpasswordportal"
      portalPassword: "dbpasswordportal"
      replicationPassword: "dbpasswordportal"
      provisioningPassword: "dbpasswordportal"
    primary:
      persistence:
        enabled: false
  portalAddress: "http://portal.tx.test"
  portalBackendAddress: "http://portal-backend.tx.test"
  centralidp:
    address: "http://centralidp.tx.test"
  sharedidpAddress: "http://sharedidp.tx.test"
  semanticsAddress: "http://semantics.tx.test"
  bpdm:
    poolAddress: "http://business-partners.tx.test"
    poolApiPath: "/pool/v6"
    portalGateAddress: "http://business-partners.tx.test"
    portalGateApiPath: "/gate/v6"
  custodianAddress: "http://ssi-dim-wallet-stub.tx.test"
  dimWrapper:
    baseAddress: "http://ssi-dim-wallet-stub.tx.test"
    apiPath: "/api/dim"
    tokenAddress: "http://ssi-dim-wallet-stub.tx.test/oauth/token"
  decentralIdentityManagementAuthAddress: "http://ssi-dim-wallet-stub.tx.test/api/sts"
  sdfactoryAddress: "http://sdfactory.tx.test"
  clearinghouseAddress: "http://validation.tx.test"
  clearinghouseTokenAddress: "http://someiam.tx.test/realms/example/protocol/openid-connect/token"
  issuerComponentAddress: "http://ssi-credential-issuer.tx.test"

centralidp:
  enabled: true
  keycloak:
    nameOverride: "centralidp"
    replicaCount: 1
    auth:
      adminPassword: "adminconsolepwcentralidp"
    postgresql:
      nameOverride: "centralidp-postgresql"
      auth:
        password: "dbpasswordcentralidp"
        postgresPassword: "dbpasswordcentralidp"
      architecture: standalone
      primary:
        persistence:
          enabled: false

sharedidp:
  enabled: true
  keycloak:
    nameOverride: "sharedidp"
    auth:
      adminPassword: "adminconsolepwsharedidp"
    postgresql:
      nameOverride: "sharedidp-postgresql"
      auth:
        password: "dbpasswordsharedidp"
        postgresPassword: "dbpasswordsharedidp"
      architecture: standalone
      primary:
        persistence:
          enabled: false

bpndiscovery:
  enabled: true
  enablePostgres: true
  bpndiscovery:
    host: semantics.tx.test
    ingress:
      enabled: true
      tls: false
      urlPrefix: "/bpndiscovery"
      className: "nginx"
    authentication: true
    idp:
      issuerUri: "http://centralidp.tx.test/auth/realms/CX-Central"
      publicClientId: "Cl22-CX-BPND"
    discoveryfinderClient:
      baseUrl: "semantics.tx.test/discoveryfinder"
      registration:
        clientId: sa-cl22-01
        clientSecret: "client-secret"
        authorizationGrantType: changeme
      schedulerCronFrequency: "0 0 */1 * * *"
      provider:
        tokenUri: "http://centralidp.tx.test/auth/realms/CX-Central/protocol/openid-connect/token"
  postgresql:
    nameOverride: "bpndiscovery-postgresql"
    primary:
      persistence:
        enabled: false
        size: 8Gi
    auth:
      password: "dbpasswordbpndiscovery"
      postgresPassword: "dbpasswordbpndiscovery"

discoveryfinder:
  enabled: true
  enablePostgres: true
  discoveryfinder:
    authentication: true
    host: semantics.tx.test
    properties:
      discoveryfinder:
        initialEndpoints:
          - type: bpn
            endpointAddress: http://portal-backend.tx.test/api/administration/Connectors/discovery
            description: Service to discover connector endpoints based on bpns
            documentation: http://portal-backend.tx.test/api/administration/swagger/index.html
    idp:
      issuerUri: "http://centralidp.tx.test/auth/realms/CX-Central"
      publicClientId: "Cl21-CX-DF"
    dataSource:
      url: "jdbc:postgresql://{{ .Release.Name }}-discoveryfinder-postgresql:5432/discoveryfinder"
    ingress:
      enabled: true
      tls: false
      urlPrefix: "/discoveryfinder"
      className: "nginx"
  postgresql:
    nameOverride: "discoveryfinder-postgresql"
    primary:
      persistence:
        enabled: false
        size: 8Gi
    auth:
      password: "dbpassworddiscoveryfinder"
      postgresPassword: "dbpassworddiscoveryfinder"

selfdescription:
  enabled: true
  sdfactory:
    secret:
      jwkSetUri: "http://centralidp.tx.test/auth/realms/CX-Central/protocol/openid-connect/certs"
      clearingHouseUri: ""
      clearingHouseServerUrl: ""
      clearingHouseRealm: ""
      clearingHouseClientId: ""
      clearingHouseClientSecret: ""
      verifycredentialsUri: ""
  ingress:
    enabled: true
    hosts:
      - host: "sdfactory.tx.test"
        paths:
          - path: "/"
            pathType: "Prefix"
    className: "nginx"

ssi-credential-issuer:
  enabled: true
  replicaCount: 1
  portalBackendAddress: "http://portal-backend.tx.test"
  walletAddress: "http://ssi-dim-wallet-stub.tx.test"
  walletTokenAddress: "http://ssi-dim-wallet-stub.tx.test/oauth/token"
  service:
    swaggerEnabled: true
    logging:
      businessLogic: "Debug"
      default: "Debug"
    portal:
      clientId: "sa-cl24-01"
      clientSecret: "changeme"
    credential:
      issuerDid: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CRHK"
      issuerBpn: "BPNL00000003CRHK"
      statusListUrl: "http://ssi-dim-wallet-stub.tx.test/status-list/BPNL00000003CRHK/8a6c7486-1e1f-4555-bdd2-1a178182651e"
      encryptionConfigIndex: 0
      encryptionConfigs:
        index0:
          encryptionKey: "deb8261ec7b89c344f1c5ef5a11606e305f14e0d231b1357d90ad0180c5081d3"
  postgresql:
    enabled: true
    nameOverride: issuer-postgresql
    architecture: standalone
    primary:
      persistence:
        enabled: false
    auth:
      postgrespassword: "dbpasswordissuer"
      password: "dbpasswordissuer"
  centralidp:
    address: "http://centralidp.tx.test"
    jwtBearerOptions:
      requireHttpsMetadata: "false"
  ingress:
    enabled: true
    className: "nginx"

dataconsumerOne:
  enabled: true
  seedTestdata: false
  nameOverride: dataconsumer-1
  secrets:
    edc-wallet-secret: changeme
  tractusx-connector:
    nameOverride: dataconsumer-1-edc
    participant:
      id: BPNL00000003AZQP
    iatp:
      id: did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003AZQP
      trustedIssuers:
        - did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CRHK
      sts:
        dim:
          url: http://ssi-dim-wallet-stub.tx.test/api/sts
        oauth:
          token_url: http://ssi-dim-wallet-stub.tx.test/oauth/token
          client:
            id: BPNL00000003AZQP
            secret_alias: edc-wallet-secret
    controlplane:
      env:
        TX_IAM_IATP_CREDENTIALSERVICE_URL: http://ssi-dim-wallet-stub.tx.test/api
        EDC_IAM_DID_WEB_USE_HTTPS: false
      bdrs:
        server:
          url: http://ssi-dim-wallet-stub.tx.test/api/v1/directory
      endpoints:
        management:
          authKey: TEST1
      ingresses:
        - enabled: true
          hostname: "dataconsumer-1-controlplane.tx.test"
          endpoints:
            - default
            - protocol
            - management
          className: "nginx"
          tls:
            enabled: false
    dataplane:
      env:
        TX_IAM_IATP_CREDENTIALSERVICE_URL: http://ssi-dim-wallet-stub.tx.test/api
        EDC_IAM_DID_WEB_USE_HTTPS: false
      ingresses:
        - enabled: true
          hostname: "dataconsumer-1-dataplane.tx.test"
          endpoints:
            - default
            - public
          className: "nginx"
          tls:
            enabled: false
      token:
        signer:
          privatekey_alias: tokenSignerPrivateKey
        verifier:
          publickey_alias: tokenSignerPublicKey
    postgresql:
      nameOverride: dataconsumer-1-db
      jdbcUrl: "jdbc:postgresql://{{ .Release.Name }}-dataconsumer-1-db:5432/edc"
      auth:
        password: "dbpassworddataconsumerone"
        postgresPassword: "dbpassworddataconsumerone"
    vault:
      hashicorp:
        url: http://vault.tx.test:8200
      secretNames:
        transferProxyTokenSignerPrivateKey: tokenSignerPrivateKey
        transferProxyTokenSignerPublicKey: tokenSignerPublicKey
        transferProxyTokenEncryptionAesKey: tokenEncryptionAesKey

  vault:
    enabled: false  # Using external vault

  digital-twin-registry:
    enabled: false

  simple-data-backend:
    enabled: false

tx-data-provider:
  enabled: true
  seedTestdata: true
  backendUrl: http://{{ .Release.Name }}-dataprovider-submodelserver:8080
  registryUrl: http://{{ .Release.Name }}-dataprovider-dtr:8080/api/v3
  controlplanePublicUrl: http://{{ .Release.Name }}-dataprovider-edc-controlplane:8084
  controlplaneManagementUrl: http://{{ .Release.Name }}-dataprovider-edc-controlplane:8081
  dataplaneUrl: http://{{ .Release.Name }}-dataprovider-edc-dataplane:8081
  nameOverride: dataprovider
  secrets:
    edc-wallet-secret: changeme
  tractusx-connector:
    nameOverride: dataprovider-edc
    participant:
      id: BPNL00000003CRHK
    iatp:
      id: did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CRHK
      trustedIssuers:
        - did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CRHK
      sts:
        dim:
          url: http://ssi-dim-wallet-stub.tx.test/api/sts
        oauth:
          token_url: http://ssi-dim-wallet-stub.tx.test/oauth/token
          client:
            id: BPNL00000003CRHK
            secret_alias: edc-wallet-secret
    controlplane:
      env:
        TX_IAM_IATP_CREDENTIALSERVICE_URL: http://ssi-dim-wallet-stub.tx.test/api
        EDC_IAM_DID_WEB_USE_HTTPS: false
      bdrs:
        server:
          url: http://ssi-dim-wallet-stub.tx.test/api/v1/directory
      endpoints:
        management:
          authKey: TEST2
      ingresses:
        - enabled: true
          hostname: "dataprovider-controlplane.tx.test"
          endpoints:
            - default
            - protocol
            - management
          className: "nginx"
          tls:
            enabled: false
    dataplane:
      env:
        TX_IAM_IATP_CREDENTIALSERVICE_URL: http://ssi-dim-wallet-stub.tx.test/api
        EDC_IAM_DID_WEB_USE_HTTPS: false
      ingresses:
        - enabled: true
          hostname: "dataprovider-dataplane.tx.test"
          endpoints:
            - default
            - public
          className: "nginx"
          tls:
            enabled: false
      token:
        signer:
          privatekey_alias: tokenSignerPrivateKey
        verifier:
          publickey_alias: tokenSignerPublicKey
    postgresql:
      nameOverride: dataprovider-db
      jdbcUrl: "jdbc:postgresql://{{ .Release.Name }}-dataprovider-db:5432/edc"
      auth:
        password: "dbpasswordtxdataprovider"
        postgresPassword: "dbpasswordtxdataprovider"
    vault:
      hashicorp:
        url: http://vault.tx.test:8200
      secretNames:
        transferProxyTokenSignerPrivateKey: tokenSignerPrivateKey
        transferProxyTokenSignerPublicKey: tokenSignerPublicKey
        transferProxyTokenEncryptionAesKey: tokenEncryptionAesKey

  vault:
    enabled: false  # Using external vault

  digital-twin-registry:
    nameOverride: dataprovider-dtr
    postgresql:
      nameOverride: dataprovider-dtr-db
      auth:
        password: "dbpassworddtrdataprovider"
        existingSecret: dataprovider-secret-dtr-postgres-init
    registry:
      host: dataprovider-dtr.test

  simple-data-backend:
    nameOverride: dataprovider-submodelserver
    ingress:
      enabled: true
      className: "nginx"
      hosts:
        - host: "dataprovider-submodelserver.tx.test"
          paths:
            - path: "/"
              pathType: "Prefix"

semantic-hub:
  enabled: true
  enableKeycloak: false
  keycloak:
    postgresql:
      architecture: standalone
      primary:
        persistence:
          enabled: false
  hub:
    authentication: false
    livenessProbe:
      initialDelaySeconds: 200
    readinessProbe:
      initialDelaySeconds: 200
    host: semantics.tx.test
    ingress:
      enabled: true
      tls: false
      urlPrefix: "/hub"
      className: "nginx"
  graphdb:
    enabled: true
    image: jena-fuseki-docker:5.0.0
    imagePullPolicy: Never
    storageClassName: ""
    storageSize: 8Gi

dataconsumerTwo:
  enabled: true
  seedTestdata: false
  nameOverride: dataconsumer-2
  secrets:
    edc-wallet-secret: changeme
  tractusx-connector:
    nameOverride: dataconsumer-2-edc
    participant:
      id: BPNL00000003AVTH
    iatp:
      id: did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003AVTH
      trustedIssuers:
        - did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CRHK
      sts:
        dim:
          url: http://ssi-dim-wallet-stub.tx.test/api/sts
        oauth:
          token_url: http://ssi-dim-wallet-stub.tx.test/oauth/token
          client:
            id: BPNL00000003AVTH
            secret_alias: edc-wallet-secret
    controlplane:
      env:
        TX_IAM_IATP_CREDENTIALSERVICE_URL: http://ssi-dim-wallet-stub.tx.test/api
        EDC_IAM_DID_WEB_USE_HTTPS: false
      bdrs:
        server:
          url: http://ssi-dim-wallet-stub.tx.test/api/v1/directory
      endpoints:
        management:
          authKey: TEST3
      ingresses:
        - enabled: true
          hostname: "dataconsumer-2-controlplane.tx.test"
          endpoints:
            - default
            - protocol
            - management
          className: "nginx"
          tls:
            enabled: false
    dataplane:
      env:
        TX_IAM_IATP_CREDENTIALSERVICE_URL: http://ssi-dim-wallet-stub.tx.test/api
        EDC_IAM_DID_WEB_USE_HTTPS: false
      ingresses:
        - enabled: true
          hostname: "dataconsumer-2-dataplane.tx.test"
          endpoints:
            - default
            - public
          className: "nginx"
          tls:
            enabled: false
      token:
        signer:
          privatekey_alias: tokenSignerPrivateKey
        verifier:
          publickey_alias: tokenSignerPublicKey
    postgresql:
      nameOverride: dataconsumer-2-db
      jdbcUrl: "jdbc:postgresql://{{ .Release.Name }}-dataconsumer-2-db:5432/edc"
      auth:
        password: "dbpassworddataconsumertwo"
        postgresPassword: "dbpassworddataconsumertwo"
    vault:
      hashicorp:
        url: http://vault.tx.test:8200
      secretNames:
        transferProxyTokenSignerPrivateKey: tokenSignerPrivateKey
        transferProxyTokenSignerPublicKey: tokenSignerPublicKey
        transferProxyTokenEncryptionAesKey: tokenEncryptionAesKey

  vault:
    enabled: false  # Using external vault

  digital-twin-registry:
    enabled: false

  simple-data-backend:
    enabled: false

bdrs-server-memory:
  nameOverride: bdrs-server
  fullnameOverride: bdrs-server
  enabled: true
  seeding:
    url: "http://bdrs-server:8081"
    enabled: true
    bpnList:
      - bpn: "BPNL00000003CRHK"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CRHK"
      - bpn: "BPNL00000003B3NX"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003B3NX"
      - bpn: "BPNL00000003CSGV"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CSGV"
      - bpn: "BPNL00000003B6LU"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003B6LU"
      - bpn: "BPNL00000003AXS3"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003AXS3"
      - bpn: "BPNL00000003AZQP"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003AZQP"
      - bpn: "BPNL00000003AWSS"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003AWSS"
      - bpn: "BPNL00000003AYRE"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003AYRE"
      - bpn: "BPNL00000003AVTH"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003AVTH"
      - bpn: "BPNL00000000BJTL"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000000BJTL"
      - bpn: "BPNL00000003CML1"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CML1"
      - bpn: "BPNL00000003B2OM"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003B2OM"
      - bpn: "BPNL00000003B0Q0"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003B0Q0"
      - bpn: "BPNL00000003B5MJ"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003B5MJ"
      - bpn: "BPNS0000000008ZZ"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNS0000000008ZZ"
      - bpn: "BPNL00000003CNKC"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CNKC"
      - bpn: "BPNS00000008BDFH"
        did: "did:web:ssi-dim-wallet-stub.tx.test:BPNS00000008BDFH"

  server:
    trustedIssuers:
      - did:web:ssi-dim-wallet-stub.tx.test:BPNL00000003CRHK
    env:
      EDC_IAM_DID_WEB_USE_HTTPS: false
    endpoints:
      management:
        authKey: TEST
    ingresses:
      - enabled: true
        hostname: bdrs-server.tx.test
        endpoints:
          - directory
          - management
        className: "nginx"
        tls:
          enabled: false

bpdm:
  enabled: true
  postgres:
    enabled: true
    nameOverride: bpdm-postgres
    fullnameOverride: bpdm-postgres
    primary:
      persistence:
        enabled: false
    auth:
      password: "dbpasswordbpdm"
      postgresPassword: "dbpasswordbpdm"

  # Configures the central business partner Gate
  bpdm-gate:
    postgres:
      fullnameOverride: bpdm-postgres
      nameOverride: bpdm-postgres
    ingress:
      enabled: true
      annotations:
        nginx.ingress.kubernetes.io/rewrite-target: "/$2"
        nginx.ingress.kubernetes.io/use-regex: "true"
        nginx.ingress.kubernetes.io/x-forwarded-prefix: "/gate"
      hosts:
        - host: "business-partners.tx.test"
          paths:
            - path: "/gate(/|$)(.*)"
              pathType: "ImplementationSpecific"
    applicationConfig:
      server:
        forward-headers-strategy: "FRAMEWORK"
      bpdm:
        datasource:
          host: bpdm-postgres
        bpn:
          owner-bpn-l:
        security:
          auth-server-url: "http://centralidp.tx.test/auth"
          realm: "CX-Central"
          client-id: "Cl16-CX-BPDMGate"
        client:
          pool:
            base-url: http://business-partners.tx.test/pool
            registration:
              client-id: "sa-cl7-cx-1"
          orchestrator:
            base-url: http://business-partners.tx.test/orchestrator
            registration:
              client-id: "sa-cl25-cx-3"
    applicationSecrets:
      spring:
        datasource:
          password: "dbpasswordbpdm"
      bpdm:
        client:
          orchestrator:
            registration:
              client-secret: "changeme"
          pool:
            registration:
              client-secret: "changeme"

  # Configures the central business partner Pool
  bpdm-pool:
    postgres:
      fullnameOverride: bpdm-postgres
      nameOverride: bpdm-postgres
    ingress:
      enabled: true
      annotations:
        nginx.ingress.kubernetes.io/rewrite-target: "/$2"
        nginx.ingress.kubernetes.io/use-regex: "true"
        nginx.ingress.kubernetes.io/x-forwarded-prefix: "/pool"
      hosts:
        - host: "business-partners.tx.test"
          paths:
            - path: "/pool(/|$)(.*)"
              pathType: "ImplementationSpecific"
    applicationConfig:
      server:
        forward-headers-strategy: "FRAMEWORK"
      bpdm:
        datasource:
          host: bpdm-postgres
        security:
          auth-server-url: "http://centralidp.tx.test/auth"
          realm: "CX-Central"
          client-id: "Cl7-CX-BPDM"
        client:
          orchestrator:
            base-url: http://business-partners.tx.test/orchestrator
            registration:
              client-id: "sa-cl25-cx-2"
    applicationSecrets:
      bpdm:
        client:
          orchestrator:
            registration:
              client-secret: "changeme"
      spring:
        datasource:
          password: "dbpasswordbpdm"

  # Configures the central service for orchestrating the Golden Record Process
  bpdm-orchestrator:
    ingress:
      enabled: true
      annotations:
        nginx.ingress.kubernetes.io/rewrite-target: "/$2"
        nginx.ingress.kubernetes.io/use-regex: "true"
        nginx.ingress.kubernetes.io/x-forwarded-prefix: "/orchestrator"
      hosts:
        - host: "business-partners.tx.test"
          paths:
            - path: "/orchestrator(/|$)(.*)"
              pathType: "ImplementationSpecific"
    postgres:
      enabled: false
      fullnameOverride: bpdm-postgres
    applicationConfig:
      server:
        forward-headers-strategy: "FRAMEWORK"
      bpdm:
        datasource:
          host: bpdm-postgres
        security:
          auth-server-url: "http://centralidp.tx.test/auth"
          realm: "CX-Central"
          client-id: "Cl25-CX-BPDM-Orchestrator"
    applicationSecrets:
      spring:
        datasource:
          password: "dbpasswordbpdm"

  # This installs a dummy cleaning service which performs rudimentary cleaning operations
  bpdm-cleaning-service-dummy:
    applicationConfig:
      bpdm:
        client:
          orchestrator:
            base-url: http://business-partners.tx.test/orchestrator
            provider:
              issuer-uri: "http://centralidp.tx.test/auth/realms/CX-Central"
            registration:
              client-id: "sa-cl25-cx-1"
    applicationSecrets:
      bpdm:
        client:
          orchestrator:
            registration:
              client-secret: "changeme"

ssi-dim-wallet-stub:
  enabled: true
  wallet:
    replicaCount: 1
    host: ssi-dim-wallet-stub.tx.test
    nameSpace: "umbrella"
    appName: "ssi-dim-wallet-stub"
    configName: "ssi-dim-wallet-config"
    serviceName: "ssi-dim-wallet-service"
    secretName: "ssi-dim-wallet-secret"
    ingressName: "ssi-dim-wallet-ingress"
    seeding:
      bpnList: "BPNL00000003AZQP,BPNL00000003AYRE"
    ingress:
      enabled: true
      tls:
        enabled: false
        name: ""
      urlPrefix: /
      className: nginx
      annotations: {}
    swagger:
      ui:
        status: true
      apiDoc:
        status: true
    logLevel: "debug"
    environment: "default"
    baseWalletBpn: "BPNL00000003CRHK"
    didHost: "ssi-dim-wallet-stub.tx.test"
    stubUrl: "http://ssi-dim-wallet-stub.tx.test"
    statusListVcId: "8a6c7486-1e1f-4555-bdd2-1a178182651e"
    tokenExpiryTime: "5"
    portal:
      waitTime: "60"
      host: "http://portal-backend.tx.test"
      clientId: "sa-cl2-05"
      clientSecret: "changeme"
    keycloak:
      realm: "CX-Central"
      authServerUrl: "http://centralidp.tx.test/auth"
    service:
      type: ClusterIP
      port: 8080
  keycloak:
    enabled: false

# Disable observability components
grafana:
  enabled: false
loki:
  enabled: false
opentelemetry-collector:
  enabled: false
prometheus:
  enabled: false
jaeger:
  enabled: false

# Disable auxiliary components
pgadmin4:
  enabled: false

smtp4dev:
  enabled: false
```

### Step 2: Deploy the Umbrella Chart

```bash
# Add the Tractus-X Helm repository (if not already added)
helm repo add tractusx https://eclipse-tractusx.github.io/charts/dev
helm repo update

# Install the umbrella chart with custom values
helm install umbrella tractusx/umbrella \
  --namespace default \
  --create-namespace \
  --values custom-values.yaml \
  --wait \
  --timeout 30m
```

### Step 3: Monitor Deployment

```bash
# Check deployment status
kubectl get pods -w

# Check ingress resources
kubectl get ingress

# Check services
kubectl get svc

# Check persistent volumes
kubectl get pv,pvc
```

### Step 4: Verify Vault Integration

```bash
# Test Vault connectivity from within the cluster
kubectl run vault-test --rm -i --tty --image=vault:latest -- sh

# Inside the pod, test vault connection
export VAULT_ADDR=http://vault.tx.test:8200
export VAULT_TOKEN=$ROOT_TOKEN  # Use the root token from initialization
vault status
vault kv list secret/
exit
```
```

## Post-Deployment Verification

### Step 1: Check All Components Are Running

```bash
# Check all pods are in Running state
kubectl get pods -o wide

# Check for any failed pods
kubectl get pods --field-selector=status.phase!=Running

# Check logs for any errors
kubectl logs -l app=portal-backend
kubectl logs -l app=centralidp
kubectl logs -l app=dataconsumer-1-edc-controlplane
```

### Step 2: Test Service Endpoints

```bash
# Test portal access
curl -I http://portal.tx.test

# Test central IDP
curl -I http://centralidp.tx.test/auth/

# Test data consumer endpoints
curl -I http://dataconsumer-1-controlplane.tx.test/health
curl -I http://dataconsumer-1-dataplane.tx.test/health

# Test data provider endpoints
curl -I http://dataprovider-controlplane.tx.test/health
curl -I http://dataprovider-dataplane.tx.test/health

# Test BDRS
curl -I http://bdrs-server.tx.test/health

# Test SSI DIM Wallet Stub
curl -I http://ssi-dim-wallet-stub.tx.test/health
```

### Step 3: Verify Vault Integration

```bash
# Check if EDC components can access vault secrets
kubectl logs -l app=dataconsumer-1-edc-controlplane | grep -i vault
kubectl logs -l app=dataprovider-edc-controlplane | grep -i vault
kubectl logs -l app=dataconsumer-2-edc-controlplane | grep -i vault
```

## Troubleshooting

### Common Issues and Solutions

1. **Pods stuck in Pending state**
   ```bash
   kubectl describe pod <pod-name>
   kubectl get events --sort-by='.lastTimestamp'
   ```

2. **Database connection issues**
   ```bash
   kubectl logs -l app=portal-backend | grep -i database
   kubectl logs -l app=centralidp | grep -i database
   ```

3. **Vault connection issues**
   ```bash
   # Check vault service
   kubectl get svc -n vault
   
   # Check vault status
   kubectl logs -l app.kubernetes.io/name=vault -n vault
   
   # Test vault connectivity
   kubectl run test-vault --rm -i --tty --image=curlimages/curl -- curl -I http://vault.tx.test:8200/v1/sys/health
   
   # If Vault is sealed, unseal it
   kubectl port-forward -n vault svc/vault 8200:8200 &
   export VAULT_ADDR=http://localhost:8200
   vault status
   # If sealed, use the keys from vault-keys.json to unseal
   ```

4. **Ingress issues**
   ```bash
   kubectl get ingress
   kubectl describe ingress <ingress-name>
   ```

5. **Resource constraints**
   ```bash
   kubectl top nodes
   kubectl top pods
   ```

### Scaling Considerations

- **Memory**: Ensure your cluster has at least 16GB RAM available
- **CPU**: Ensure your cluster has at least 8 CPU cores available
- **Storage**: Ensure sufficient storage for databases (if persistence is enabled)

## Cleanup

To uninstall the deployment:

```bash
# Uninstall the umbrella chart
helm uninstall umbrella

# Uninstall vault (if using Helm)
helm uninstall vault -n vault

# Remove the namespace
kubectl delete namespace vault

# Remove DNS entries from hosts file
# Remove the vault.tx.test entry from /etc/hosts
```

## Security Considerations

1. **Change default passwords** in production
2. **Enable TLS** for all ingress resources
3. **Use proper Vault authentication** instead of root token
4. **Implement network policies** to restrict pod-to-pod communication
5. **Enable RBAC** and use service accounts with minimal privileges
6. **Regular security updates** for all components
7. **Secure Vault keys**: Store vault-keys.json securely and backup the unseal keys
8. **Vault auto-unseal**: Consider using auto-unseal for production environments
9. **Vault audit logging**: Enable audit logging for security compliance

## Support and Documentation

- [Tractus-X Umbrella Documentation](https://github.com/eclipse-tractusx/tractus-x-umbrella/tree/main/docs)
- [Installation Guide](https://github.com/eclipse-tractusx/tractus-x-umbrella/tree/main/docs/user/installation)
- [Network Setup](https://github.com/eclipse-tractusx/tractus-x-umbrella/tree/main/docs/user/network)
- [User Guides](https://github.com/eclipse-tractusx/tractus-x-umbrella/tree/main/docs/user/guides)

---

**Note**: This deployment plan is based on Tractus-X Umbrella version 2.12.2. Always refer to the latest documentation for the most up-to-date information and best practices.
