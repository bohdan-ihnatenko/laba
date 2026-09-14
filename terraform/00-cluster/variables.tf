variable "cluster_name" {
  description = "Имя k3d-кластера"
  type        = string
  default     = "lab"
}

variable "corporate_ca_cert_path" {
  description = "Абсолютный путь к корневому сертификату корпоративного CA (тот, что подсовывает VPN/прокси при TLS-инспекции). Пустая строка — не монтировать ничего."
  type        = string
  default     = "/Users/admina/ca_prizma.pem"
}
