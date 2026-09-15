output "argocd_url" {
  description = "Публичный адрес ArgoCD UI через Cloudflare Tunnel + Gateway API"
  value       = "https://argocd.${var.domain}"
}

output "vault_url" {
  description = "Публичный адрес Vault UI через Cloudflare Tunnel + Gateway API (без Access — лаба)"
  value       = "https://vault.${var.domain}"
}

output "cloudflare_tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.lab.id
}
