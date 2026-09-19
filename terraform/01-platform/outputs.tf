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

output "r2_bucket_name" {
  value = cloudflare_r2_bucket.petclinic_backups.name
}

output "r2_s3_endpoint" {
  description = "Подставь в spec.backups.pgbackrest.repos[].s3.endpoint у PostgresCluster petclinic (сейчас там плейсхолдер <ACCOUNT_ID>)"
  value       = "${var.cloudflare_account_id}.r2.cloudflarestorage.com"
}
