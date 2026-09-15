# Cloud-часть туннеля: сам объект туннеля, remote-управляемый ingress-конфиг
# и DNS-записи. Домен на этот момент уже должен быть добавлен в Cloudflare
# как Site (см. README) — иначе cloudflare_zone_id взять неоткуда.

resource "cloudflare_zero_trust_tunnel_cloudflared" "lab" {
  account_id = var.cloudflare_account_id
  name       = "k3d-${var.cluster_name}"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "lab" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.lab.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "lab" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.lab.id

  config = {
    ingress = [
      {
        # ЕДИНСТВЕННОЕ ingress-правило, которое тут когда-либо должно быть.
        # Весь HTTP-трафик на любой поддомен уходит в Gateway API (Traefik) —
        # какой хостнейм на какой сервис, решает уже не Terraform, а
        # HTTPRoute-манифесты в GitOps (gitops/routes/*.yaml). Новый сервис
        # наружу — это git commit в routes/, а не terraform apply здесь.
        hostname = "*.${var.domain}"
        service  = "http://traefik.traefik.svc.cluster.local:80"
      },
      {
        # catch-all — обязателен последним правилом, иначе провайдер ругнётся
        service = "http_status:404"
      },
    ]
  }
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.lab.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # 1 = "Auto", обязательно при proxied = true
}
