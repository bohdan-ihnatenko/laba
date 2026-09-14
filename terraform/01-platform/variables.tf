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

variable "corporate_ca_cert_path" {
  description = "Абсолютный путь к корневому сертификату корпоративного CA (тот же файл, что и в 00-cluster). Пустая строка — не монтировать ничего."
  type        = string
  default     = "/Users/admina/ca_prizma.pem"
}
