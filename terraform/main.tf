terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    null = {
      source = "hashicorp/null"
      version = ">= 3.0"
    }
    local = {
      source = "hashicorp/local"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}

# Kubernetes provider will be configured after minikube is ready

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

resource "null_resource" "minikube" {
  provisioner "local-exec" {
    command = <<EOT
      minikube start --cpus=${var.cluster_cpus} --memory=${var.cluster_memory}gb --profile='${var.cluster_name}'
      minikube profile ${var.cluster_name}
      minikube addons enable metrics-server
      minikube addons enable ingress
      minikube addons enable ingress-dns
      minikube ip --profile='${var.cluster_name}' | tr -d '\n' > minikube_ip.txt
    EOT
  }
}

data "local_file" "minikube_ip" {
  filename = "${path.module}/minikube_ip.txt"
  depends_on = [null_resource.minikube]
}

# Configure Kubernetes provider after minikube is ready
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube-${var.cluster_name}"
  depends_on     = [null_resource.minikube]
}

# Configure Helm provider
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube-${var.cluster_name}"
  }
  depends_on = [null_resource.minikube]
}

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

# Install ArgoCD using Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = "5.51.6"

  depends_on = [null_resource.install_vault]

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
    name  = "server.ingress.annotations.kubernetes\\.io/ingress\\.class"
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
    name  = "server.ingress.tls[0].secretName"
    value = "argocd-server-tls"
  }

  set {
    name  = "server.ingress.tls[0].hosts[0]"
    value = "argo.tx.test"
  }

  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  set {
    name  = "server.extraArgs[1]"
    value = "--rootpath"
  }

  set {
    name  = "server.extraArgs[2]"
    value = "/"
  }

  set {
    name  = "configs.secret.argocdServerAdminPassword"
    value = "admin123"
  }
}

# Create ArgoCD Application for umbrella deployment
resource "kubernetes_manifest" "umbrella_application" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "umbrella"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/aminshuvo/tractus-x-umbrella-umbrella"
        targetRevision = "main"
        path          = "charts/umbrella"
        helm = {
          valueFiles = ["values-dev.yaml"]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "umbrella"
      }
      syncPolicy = {
        automated = {
          prune      = true
          selfHeal   = true
          allowEmpty = false
        }
        syncOptions = [
          "CreateNamespace=true",
          "PrunePropagationPolicy=foreground",
          "PruneLast=true"
        ]
      }
    }
  }
}

# Wait for ArgoCD to be ready
resource "null_resource" "wait_for_argocd" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command = <<EOT
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n argocd
    EOT
  }
}

# Print ArgoCD admin password
resource "null_resource" "print_argocd_info" {
  depends_on = [null_resource.wait_for_argocd]

  provisioner "local-exec" {
    command = <<EOT
      echo "=== ArgoCD Setup Complete ==="
      echo "ArgoCD URL: http://argo.tx.test"
      echo "Username: admin"
      echo "Password: admin123"
      echo ""
      echo "Please add the following entry to your /etc/hosts file:"
      echo "$(cat minikube_ip.txt) argo.tx.test"
      echo ""
      echo "You can also access ArgoCD via port-forward:"
      echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
      echo "Then visit: https://localhost:8080"
    EOT
  }
} 