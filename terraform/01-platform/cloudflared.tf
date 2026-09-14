# Демон, который реально держит исходящее соединение из кластера наружу.
# Секрет с токеном туннеля пока лежит тут напрямую как kubernetes_secret —
# это временное решение до тех пор, пока не поднят Vault + External Secrets.
# Как только они появятся — этот kubernetes_secret удаляется, а токен туда
# кладёт Terraform через modules/vault/secret-аналог, а в кластер его тянет ESO.

resource "kubernetes_namespace" "cloudflared" {
  metadata {
    name = "cloudflared"
  }
}

resource "kubernetes_secret" "tunnel_token" {
  metadata {
    name      = "cloudflared-tunnel-token"
    namespace = kubernetes_namespace.cloudflared.metadata[0].name
  }

  data = {
    token = data.cloudflare_zero_trust_tunnel_cloudflared_token.lab.token
  }
}

# Тот же корпоративный CA, что рвал TLS для docker.io, режет и TLS от
# cloudflared до Cloudflare edge — но это отдельный процесс со своим набором
# доверенных сертификатов, никак не связанный с тем, что уже настроено на
# уровне k3d-ноды в 00-cluster. Кладём CA как ConfigMap и говорим cloudflared
# (это Go-бинарник) доверять именно ему через переменную окружения SSL_CERT_FILE.
resource "kubernetes_config_map" "corporate_ca" {
  count = var.corporate_ca_cert_path != "" ? 1 : 0

  metadata {
    name      = "corporate-ca"
    namespace = kubernetes_namespace.cloudflared.metadata[0].name
  }

  data = {
    "ca.crt" = file(var.corporate_ca_cert_path)
  }
}

resource "kubernetes_deployment" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace.cloudflared.metadata[0].name
  }

  spec {
    replicas = 2 # cloudflared умеет несколько реплик одного туннеля из коробки

    selector {
      match_labels = { app = "cloudflared" }
    }

    template {
      metadata {
        labels = { app = "cloudflared" }
      }

      spec {
        dynamic "volume" {
          for_each = var.corporate_ca_cert_path != "" ? [1] : []
          content {
            name = "corporate-ca"
            config_map {
              name = kubernetes_config_map.corporate_ca[0].metadata[0].name
            }
          }
        }

        container {
          name  = "cloudflared"
          image = var.cloudflared_image
          args  = ["tunnel", "--no-autoupdate", "--protocol", "http2", "run"]

          dynamic "volume_mount" {
            for_each = var.corporate_ca_cert_path != "" ? [1] : []
            content {
              name       = "corporate-ca"
              mount_path = "/etc/cloudflared/certs"
              read_only  = true
            }
          }

          dynamic "env" {
            for_each = var.corporate_ca_cert_path != "" ? [1] : []
            content {
              name  = "SSL_CERT_FILE"
              value = "/etc/cloudflared/certs/ca.crt"
            }
          }

          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tunnel_token.metadata[0].name
                key  = "token"
              }
            }
          }
        }
      }
    }
  }
}
