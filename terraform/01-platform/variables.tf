variable "cloudflare_api_token" {
  description = "API-токен Cloudflare с правами Zone:DNS Edit + Account:Cloudflare Tunnel Edit на нужный zone/account"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Account ID из Cloudflare Dashboard (правая колонка на странице обзора любого домена)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Zone ID вашего домена после того, как он добавлен как Site в Cloudflare"
  type        = string
}

variable "domain" {
  description = "Ваш корневой домен, например example.com"
  type        = string
}

variable "cluster_name" {
  description = "Имя k3d-кластера"
  type        = string
  default     = "lab"
}

variable "kubeconfig_path" {
  description = "Путь к kubeconfig, который пишет k3d"
  type        = string
  default     = "~/.kube/config"
}

variable "cloudflared_image" {
  description = "Образ cloudflared — проверьте актуальный тег на hub.docker.com/r/cloudflare/cloudflared/tags перед apply"
  type        = string
  default     = "cloudflare/cloudflared:2024.12.2"
}

variable "vault_addr" {
  description = "Адрес Vault API для vault-провайдера Terraform. По умолчанию localhost — перед apply, который трогает vault-провайдер, нужно руками поднять kubectl port-forward -n vault svc/vault 8200:8200 в отдельном терминале."
  type        = string
  default     = "http://127.0.0.1:8200"
}

variable "vault_root_token" {
  description = "Root-токен из vault-init.json (ручной bootstrap, см. README) — нужен только для первичной настройки auth methods/policies, нигде постоянно не хранится, кроме tfstate этого модуля"
  type        = string
  sensitive   = true
}
