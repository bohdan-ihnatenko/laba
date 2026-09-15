# Bootstrap app-of-apps: единственная Application, которую создаёт Terraform.
# Она указывает на чарт gitops/x-system в git-репозитории — дальше ArgoCD сам
# синкает оттуда всё остальное (Vault, ESO, ingress, мониторинг и т.д.), это
# уже никогда не идёт через terraform apply / helm install руками.

variable "gitops_repo_url" {
  description = "HTTPS URL git-репозитория с GitOps-манифестами, например https://github.com/<user>/terraform-laba.git"
  type        = string
}

variable "gitops_repo_revision" {
  description = "Ветка/тег/коммит, который ArgoCD должен синкать"
  type        = string
  default     = "main"
}

variable "github_username" {
  description = "GitHub-логин — используется вместе с github_pat для HTTPS-аутентификации ArgoCD к приватному репозиторию"
  type        = string
}

variable "github_pat" {
  description = "Fine-grained GitHub PAT с правом read-only на Contents именно этого репозитория — нужен ArgoCD, чтобы клонировать приватный репо"
  type        = string
  sensitive   = true
}

# Секрет в формате, который ArgoCD сам распознаёт по лейблу
# argocd.argoproj.io/secret-type: repository — без этого он не знает, какими
# кредами клонировать приватный репозиторий.
resource "kubernetes_secret" "gitops_repo_creds" {
  metadata {
    name      = "gitops-repo-creds"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.gitops_repo_url
    username = var.github_username
    password = var.github_pat
  }
}

resource "kubernetes_manifest" "x_system" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "x-system"
      namespace  = kubernetes_namespace.argocd.metadata[0].name
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_revision
        path           = "gitops/x-system"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.argocd.metadata[0].name
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_secret.gitops_repo_creds]
}
