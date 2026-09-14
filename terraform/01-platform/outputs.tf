output "argocd_url" {
  description = "Публичный адрес ArgoCD UI через Cloudflare Tunnel"
  value       = "https://argocd.${var.domain}"
}

output "cloudflare_tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.lab.id
}
