terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.12.1"
    }
    null = {
      source = "hashicorp/null"
      version = ">= 3.0"
    }
    local = {
      source = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

variable "cluster_name" {
  type    = string
  default = "tractus-x"
}

variable "cluster_cpus" {
  type    = number
  default = 8
}

variable "cluster_memory" {
  type    = number
  default = 14
}

locals {
  domains = [
    "portal.tx.test",
    "portal-backend.tx.test",
    "centralidp.tx.test",
    "sharedidp.tx.test",
    "dataprovider-controlplane.tx.test",
    "dataprovider-dataplane.tx.test",
    "dataconsumer-1-controlplane.tx.test",
    "dataconsumer-1-dataplane.tx.test",
    "dataconsumer-2-controlplane.tx.test",
    "dataconsumer-2-dataplane.tx.test",
    "semantics.tx.test",
    "business-partners.tx.test",
    "ssi-dim-wallet-stub.tx.test",
    "bdrs-server.tx.test",
    "pgadmin4.tx.test",
    "smtp.tx.test",
    "sdfactory.tx.test",
    "ssi-credential-issuer.tx.test",
    "dataprovider-submodelserver.tx.test",
    "dataprovider-dtr.tx.test",
    "vault.tx.test",
    "dataprovider-dtr.test",
    "argo.tx.test"
  ]
}

# Step 1: Setup Minikube
resource "null_resource" "minikube" {
  provisioner "local-exec" {
    command = <<EOT
      # Delete existing cluster if exists
      if minikube profile list 2>/dev/null | grep -q "${var.cluster_name}"; then
        minikube delete --profile='${var.cluster_name}'
      fi
      
      # Start Minikube
      minikube start --cpus=${var.cluster_cpus} --memory=${var.cluster_memory}gb --profile='${var.cluster_name}'
      minikube profile ${var.cluster_name}
      minikube addons enable metrics-server
      minikube addons enable ingress
      minikube addons enable ingress-dns
      minikube ip --profile='${var.cluster_name}' | tr -d '\n' > minikube_ip.txt
      
      # Set kubectl context
      kubectl config use-context ${var.cluster_name}
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "minikube delete --profile='tractus-x' || true"
  }
}

data "local_file" "minikube_ip" {
  filename = "${path.module}/minikube_ip.txt"
  depends_on = [null_resource.minikube]
}

# Step 2: Create namespaces
resource "null_resource" "create_namespaces" {
  depends_on = [null_resource.minikube]
  provisioner "local-exec" {
    command = <<EOT
      kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
      kubectl create namespace umbrella --dry-run=client -o yaml | kubectl apply -f -
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    EOT
  }
}

# Step 3: Install Vault using your custom script
resource "null_resource" "install_vault" {
  depends_on = [null_resource.create_namespaces]
  provisioner "local-exec" {
    command = <<EOT
      cd ../vault
      chmod +x install_vault.sh
      ./install_vault.sh
    EOT
  }
}

# Configure providers after cluster is ready
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.cluster_name
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.cluster_name
  }
}

# Step 4: Install ArgoCD using Helm (simplified)
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = "5.51.6"

  depends_on = [null_resource.install_vault]

  # Basic server configuration only
  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.hosts[0]"
    value = "argo.tx.test"
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "nginx"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/ssl-redirect"
    value = "false"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/force-ssl-redirect"
    value = "false"
  }

  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  set {
    name  = "configs.secret.argocdServerAdminPassword"
    value = "admin123"
  }
}

# Wait for ArgoCD to be ready (simplified)
resource "null_resource" "wait_for_argocd" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command = <<EOT
      # Simple wait approach - just check if key pods are running
      echo "Waiting for ArgoCD pods to be ready..."
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=300s
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=300s
      
      echo "ArgoCD is ready!"
    EOT
  }
}

# Step 5: Apply ArgoCD applications from ../argocd directory
resource "null_resource" "apply_argocd_apps" {
  depends_on = [null_resource.wait_for_argocd]

  provisioner "local-exec" {
    command = <<EOT
      # Apply ArgoCD application configurations
      if [ -d "../argocd/applications" ]; then
        kubectl apply -f ../argocd/applications/
        echo "Applied ArgoCD applications"
      else
        echo "No ArgoCD applications directory found"
      fi
      
      if [ -d "../argocd/projects" ]; then
        kubectl apply -f ../argocd/projects/
        echo "Applied ArgoCD projects"
      fi
      
      if [ -d "../argocd/repositories" ]; then
        kubectl apply -f ../argocd/repositories/
        echo "Applied ArgoCD repositories"
      fi
    EOT
  }
}

# Generate hosts entry
resource "local_file" "hosts_entry" {
  content  = "${data.local_file.minikube_ip.content} ${join(" ", local.domains)}\n"
  filename = "${path.module}/hosts_entry.txt"
  depends_on = [data.local_file.minikube_ip]
}

# Print final info
resource "null_resource" "print_argocd_info" {
  depends_on = [null_resource.apply_argocd_apps, local_file.hosts_entry]

  provisioner "local-exec" {
    command = <<EOT
      echo "=== Tractus-X Development Environment Ready ==="
      echo "ArgoCD URL: http://argo.tx.test"
      echo "Username: admin"
      echo "Password: admin123"
      echo ""
      echo "Minikube IP: $(cat minikube_ip.txt)"
      echo ""
      echo "Add to /etc/hosts:"
      cat hosts_entry.txt
      echo ""
      echo "Check ArgoCD applications:"
      echo "kubectl get applications -n argocd"
      echo ""
      echo "Port-forward alternative:"
      echo "kubectl port-forward svc/argocd-server -n argocd 8080:80"
    EOT
  }
}

# Outputs
output "minikube_ip" {
  value = data.local_file.minikube_ip.content
}

output "argocd_url" {
  value = "http://argo.tx.test"
}

output "hosts_entry" {
  value = local_file.hosts_entry.content
} 
