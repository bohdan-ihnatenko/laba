# Настройка самого Vault под ESO. Сознательно идёт через vault-провайдер
# Terraform, а НЕ через ArgoCD/GitOps: сюда нужен root-токен от ручного
# bootstrap'а (vault-init.json), а привилегированные креды в git не кладём —
# тот же принцип, что и с самим init/unseal. Подключение — через
# kubectl port-forward -n vault svc/vault 8200:8200 (см. variables.tf).

resource "kubernetes_cluster_role_binding" "vault_tokenreview" {
  metadata {
    name = "vault-tokenreview-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "vault"
    namespace = "vault"
  }
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "this" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc"
  # kubernetes_ca_cert / token_reviewer_jwt намеренно не заданы: Vault сам
  # возьмёт их из смонтированного токена своего собственного пода — штатное
  # поведение, когда Vault и есть под в том же кластере, который проверяет.

  depends_on = [kubernetes_cluster_role_binding.vault_tokenreview]
}

resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv-v2"
  description = "KV v2 для секретов приложений — отсюда читает ESO"
}

resource "vault_policy" "eso_read" {
  name = "eso-read"

  policy = <<-EOT
    path "secret/data/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/*" {
      capabilities = ["list"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "eso" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "eso"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = [vault_policy.eso_read.name]
  token_ttl                        = 3600
}
