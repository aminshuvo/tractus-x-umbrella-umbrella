# Tractus-X Umbrella - Manual Installation Guide

This repository contains a complete deployment setup for the **Tractus-X Umbrella** (Catena-X automotive dataspace) using Kubernetes, Helm, and HashiCorp Vault for secure secret management.

## 🏗️ Architecture Overview

The Tractus-X Umbrella provides a foundation for running end-to-end tests or creating sandbox environments of the [Catena-X](https://catena-x.net/en/) automotive dataspace using [Eclipse Tractus-X](https://projects.eclipse.org/projects/automotive.tractusx) OSS components.

![Tractus-X Umbrella Deployment](images/umbrella-deploy.png)

### Key Components:
- **Kubernetes Cluster**: Minikube-based local development environment
- **Secrets Management**: HashiCorp Vault for secure secret storage
- **Helm Charts**: Umbrella chart with multiple Tractus-X components
- **Custom Services**: Local patches for discoveryfinder, bpndiscovery, and semantic-hub

## 📋 Prerequisites

### Required Tools
Before starting the installation, ensure you have the following tools installed:

```bash
# Check tool versions
helm version
docker version
terraform version
minikube version
kubectl version --client
```

**Tested Versions:**
- **Helm**: v3.18.3
- **Docker**: 28.3.1
- **Terraform**: v1.12.2
- **Minikube**: v1.36.0
- **kubectl**: v1.33.1

**Minimum Requirements:**
- **CPU**: 8 cores
- **Memory**: 16GB RAM
- **Storage**: 20GB free space

### Required Software
- [Minikube](https://minikube.sigs.k8s.io/docs/start/) - Local Kubernetes cluster (v1.36.0+)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes command-line tool (v1.33.1+)
- [Helm](https://helm.sh/docs/intro/install/) - Kubernetes package manager (v3.18.3+)
- [Docker](https://docs.docker.com/get-docker/) - Container runtime (28.3.1+)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) - Infrastructure as Code (v1.12.2+, optional)

## 🚀 Installation Options

You have two options for deploying the Tractus-X Umbrella:

1. **[Manual Installation](#manual-installation-steps)** - Step-by-step manual setup
2. **[Automatic Installation](#automatic-installation-with-terraform-and-argocd)** - Automated setup using Terraform and ArgoCD

### Manual Installation Steps

### Step 1: Start Minikube Kubernetes Cluster

```bash
# Start Minikube with required resources
minikube start --cpus=8 --memory=16gb --profile='tractus-x'

# Set the profile
minikube profile tractus-x

# Enable required addons
minikube addons enable metrics-server
minikube addons enable ingress
minikube addons enable ingress-dns

# Create required namespaces
kubectl create ns vault
kubectl create ns umbrella
```

### Step 2: Configure DNS Entries

Get your Minikube IP and add the following entries to your `/etc/hosts` file:

```bash
# Get Minikube IP
minikube ip
```

Edit `/etc/hosts` file (requires sudo on Linux/macOS):

```bash
sudo nano /etc/hosts
```

Add the following entries (replace `<MINIKUBE_IP>` with your actual Minikube IP):

```
<MINIKUBE_IP> portal.tx.test
<MINIKUBE_IP> portal-backend.tx.test
<MINIKUBE_IP> centralidp.tx.test
<MINIKUBE_IP> sharedidp.tx.test
<MINIKUBE_IP> dataprovider-controlplane.tx.test
<MINIKUBE_IP> dataprovider-dataplane.tx.test
<MINIKUBE_IP> dataconsumer-1-controlplane.tx.test
<MINIKUBE_IP> dataconsumer-1-dataplane.tx.test
<MINIKUBE_IP> dataconsumer-2-controlplane.tx.test
<MINIKUBE_IP> dataconsumer-2-dataplane.tx.test
<MINIKUBE_IP> semantics.tx.test
<MINIKUBE_IP> business-partners.tx.test
<MINIKUBE_IP> ssi-dim-wallet-stub.tx.test
<MINIKUBE_IP> bdrs-server.tx.test
<MINIKUBE_IP> pgadmin4.tx.test
<MINIKUBE_IP> smtp.tx.test
<MINIKUBE_IP> sdfactory.tx.test
<MINIKUBE_IP> ssi-credential-issuer.tx.test
<MINIKUBE_IP> dataprovider-submodelserver.tx.test
<MINIKUBE_IP> dataprovider-dtr.tx.test
<MINIKUBE_IP> vault.tx.test
<MINIKUBE_IP> dataprovider-dtr.test
<MINIKUBE_IP> argo.tx.test
```

### Step 3: Install and Configure Vault

```bash
# Navigate to vault directory
cd vault

# Make the installation script executable
chmod +x install_vault.sh

# Run the Vault installation script
./install_vault.sh
```

The script will automatically:
- Install HashiCorp Vault using Helm
- Initialize Vault with 5 unseal keys (threshold: 3)
- Unseal Vault using the first 3 keys
- Configure KV secrets engine
- Create secrets for EDC components
- Set up access policies and tokens
- Generate `vault-edc-token-secret.yaml`

After the script completes, apply the generated secret to the umbrella namespace:

```bash
# Apply the Vault token secret to umbrella namespace
kubectl -n umbrella apply -f vault-edc-token-secret.yaml
```

### Step 4: Install Tractus-X Umbrella

```bash
# Navigate to the umbrella chart directory
cd charts/umbrella

# Update Helm dependencies
helm dependency update

# Install the umbrella chart with development values
helm install umbrella . -f values-dev.yaml -n umbrella --create-namespace --timeout 15m
```

### Automatic Installation with Terraform and ArgoCD

For automated deployment using Infrastructure as Code (IaC) and GitOps, follow these steps:

#### Prerequisites for Automatic Setup

```bash
# Ensure Terraform is installed and configured
terraform version

# Verify you have access to the repository
git clone https://github.com/aminshuvo/tractus-x-umbrella-umbrella.git
cd tractus-x-umbrella-umbrella
```

#### Step 1: Initialize and Apply Terraform

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

The Terraform configuration will automatically:
- Create and configure Minikube cluster with required resources
- Set up required namespaces (vault, umbrella, argocd)
- Install and configure HashiCorp Vault
- Install ArgoCD with ingress configuration
- Apply ArgoCD applications and repositories
- Generate hosts file entries

#### Step 2: Configure DNS Entries

After Terraform completes, add the generated hosts entries to your `/etc/hosts` file:

```bash
# View the generated hosts entry
cat terraform/hosts_entry.txt

# Add to /etc/hosts (copy the output from above command)
sudo nano /etc/hosts
```

#### Step 3: Access ArgoCD and Monitor Deployment

```bash
# Get ArgoCD access information
echo "ArgoCD URL: http://argo.tx.test"
echo "Username: admin"
echo "Password: admin123 (configured in Terraform)"

# Check ArgoCD application status
kubectl get applications -n argocd

# Monitor the umbrella application
kubectl describe application umbrella -n argocd
```

#### Step 4: Verify Deployment

```bash
# Check all pods in umbrella namespace
kubectl get pods -n umbrella

# Check ArgoCD sync status
kubectl get applications -n argocd -o wide
```

### GitOps Workflow

The automatic setup uses ArgoCD for GitOps deployment:

![Tractus-X Umbrella with ArgoCD](images/umbrella-with-argo.png)

1. **Repository**: `https://github.com/aminshuvo/tractus-x-umbrella-umbrella.git`
2. **Branch**: `main`
3. **Path**: `charts/umbrella`
4. **Values**: `values-dev.yaml`
5. **Sync Policy**: Automated with self-healing enabled

#### ArgoCD Application Configuration

The ArgoCD application is configured with:
- **Automated sync**: Enabled with prune and self-heal
- **Sync options**: CreateNamespace, PrunePropagationPolicy, ServerSideApply
- **Retry policy**: 5 attempts with exponential backoff
- **Ignore differences**: Resource requirements and replicas for dev environment

## 🔧 Configuration

### Values File
The installation uses `values-dev.yaml` which includes:
- Portal configuration with backend services
- Central and Shared IDP setup
- EDC data provider and consumer components
- Semantic Hub and Business Partner Discovery
- SSI Credential Issuer
- Observability components (Prometheus, Grafana, Jaeger)

### Local Patches
This repository includes local patches for:
- **discoveryfinder**: Local patched version for enhanced discovery capabilities
- **bpndiscovery**: Local patched version for business partner discovery
- **semantic-hub**: Local patched version for semantic data management

## 🌐 Accessing Services

Once deployed, you can access the following services:

| Service | URL | Description |
|---------|-----|-------------|
| Portal | http://portal.tx.test | Main portal interface |
| Portal Backend | http://portal-backend.tx.test | Portal backend API |
| Central IDP | http://centralidp.tx.test | Central Identity Provider |
| Shared IDP | http://sharedidp.tx.test | Shared Identity Provider |
| Vault | http://vault.tx.test | HashiCorp Vault UI |
| PgAdmin | http://pgadmin4.tx.test | Database administration |
| Semantic Hub | http://semantics.tx.test | Semantic data management |
| **ArgoCD** | http://argo.tx.test | GitOps deployment management |

### ArgoCD Access Information

- **URL**: http://argo.tx.test
- **Username**: admin
- **Password**: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo`

## 🔍 Monitoring and Troubleshooting

### Check Pod Status
```bash
# Check all pods in umbrella namespace
kubectl get pods -n umbrella

# Check specific component pods
kubectl get pods -n umbrella | grep discoveryfinder
kubectl get pods -n umbrella | grep bpndiscovery
```

### View Logs
```bash
# View logs for a specific pod
kubectl logs -n umbrella <pod-name>

# Follow logs in real-time
kubectl logs -f -n umbrella <pod-name>
```

### Common Issues

#### 1. CreateContainerConfigError
If pods fail with `CreateContainerConfigError`, check for missing secrets:
```bash
# Check if required secrets exist
kubectl get secrets -n umbrella

# Common missing secrets that need to be created manually:
# - secret-discoveryfinder-postgres-init
# - secret-bpndiscovery-postgres-init
```

#### 2. Vault Connection Issues
```bash
# Check Vault status
kubectl exec -n vault deployment/vault -- vault status

# Check Vault logs
kubectl logs -n vault deployment/vault
```

#### 3. DNS Resolution Issues
```bash
# Test DNS resolution
nslookup portal.tx.test
ping portal.tx.test

# Verify hosts file entries
cat /etc/hosts | grep tx.test
```

#### 4. ArgoCD Sync Issues
```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Check ArgoCD application details
kubectl describe application umbrella -n argocd

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Force sync if needed
kubectl patch application umbrella -n argocd --type='merge' -p='{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

# Retrieve the initial ArgoCD admin password (most reliable for new installs)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
# If you have changed or upgraded, try the main secret
kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.admin\.password}' | base64 -d; echo
```

#### 5. Terraform Issues
```bash
# Check Terraform state
terraform show

# Check Terraform plan
terraform plan

# Reset Terraform state if needed
cd terraform
rm -f terraform.tfstate*
terraform init
```

## 🧹 Cleanup

### Manual Installation Cleanup

To clean up the manual deployment:

```bash
# Uninstall the umbrella chart
helm uninstall umbrella -n umbrella

# Delete namespaces
kubectl delete ns umbrella
kubectl delete ns vault

# Stop and delete Minikube cluster
minikube stop --profile='tractus-x'
minikube delete --profile='tractus-x'

# Remove hosts file entries (manually edit /etc/hosts)
```

### Automatic Installation Cleanup

To clean up the Terraform-managed deployment:

```bash
# Navigate to terraform directory
cd terraform

# Destroy all Terraform-managed resources
terraform destroy

# This will automatically:
# - Delete ArgoCD applications
# - Uninstall ArgoCD
# - Uninstall Vault
# - Delete namespaces
# - Stop and delete Minikube cluster
```

### Reset Terraform State (if needed)

If you need to completely reset the Terraform state:

```bash
# Navigate to terraform directory
cd terraform

# Remove Terraform state files
rm -f terraform.tfstate*

# Reinitialize Terraform
terraform init
```

## 📚 Additional Resources

- [Tractus-X Documentation](https://docs.catena-x.net/)
- [Eclipse Tractus-X](https://projects.eclipse.org/projects/automotive.tractusx)
- [Catena-X Network](https://catena-x.net/en/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)

## 🤝 Contributing

This repository includes local patches and customizations. When contributing:

1. Test your changes thoroughly
2. Update documentation as needed
3. Follow the existing code style
4. Ensure all components are working correctly

## 📄 License

This work is licensed under the [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/legalcode).

- SPDX-License-Identifier: CC-BY-4.0
- SPDX-FileCopyrightText: 2024 Contributors to the Eclipse Foundation

## ⚠️ Important Notes

- **Resource Requirements**: Ensure your system meets the minimum CPU and memory requirements
- **Local Development**: This setup is designed for local development and testing
- **Security**: Vault keys and tokens should be kept secure and not committed to version control
- **Persistence**: By default, persistence is disabled for development environments
- **Network**: All services use HTTP (not HTTPS) for local development

---
