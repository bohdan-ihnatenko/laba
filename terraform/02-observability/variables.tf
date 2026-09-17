variable "grafana_url" {
  description = "Публичный адрес Grafana (тот же хостнейм, что и HTTPRoute в gitops/routes/grafana.yaml)"
  type        = string
  default     = "https://grafana.hydranoid.site"
}

variable "grafana_auth" {
  description = "Креды Grafana в формате \"user:password\" (то же самое, что провайдер принимает и через переменную окружения GRAFANA_AUTH) — тот же admin/пароль, что лежит в Vault secret/grafana и синкается ESO в K8s Secret grafana-admin-credentials. Пока это basic-auth админом; завести отдельный service account token — отдельный шаг на будущее."
  type        = string
  sensitive   = true
}

variable "slack_webhook" {
  description = "Slack Webhok"
  type = string
  sensitive = true
}
