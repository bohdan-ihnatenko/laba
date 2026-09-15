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
        container {
          name  = "cloudflared"
          image = var.cloudflared_image
          args  = ["tunnel", "--no-autoupdate", "--protocol", "http2", "run"]

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
