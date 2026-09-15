variable "cluster_name" {
  description = "Имя k3d-кластера"
  type        = string
  default     = "lab"
}

variable "remote_docker_host" {
  description = "DOCKER_HOST для удалённого Docker-движка, например ssh://bohdan@homehost.local. Кластер физически создаётся на этой машине, а k3d/terraform продолжают выполняться там, где сейчас (рабочий ноут). Пустая строка — использовать локальный Docker текущей машины."
  type        = string
  default     = ""
}

variable "remote_api_host" {
  description = "IP или mDNS-имя (например homehost.local) машины, на которой реально живёт кластер — нужен только когда remote_docker_host непустой. k3s API будет слушать на этом адресе, и он же попадёт в SAN TLS-сертификата, иначе kubectl с этой машины получит x509: certificate is valid for ..., not <адрес>."
  type        = string
  default     = ""
}

variable "kubeconfig_path" {
  description = "Путь к kubeconfig, в который k3d допишет контекст этого кластера. Это ВСЕГДА локальный файл именно той машины, где выполняется terraform apply / k3d CLI (сейчас — рабочий ноут), и не зависит от того, где физически поднят Docker-движок (см. remote_docker_host) — задаём его явно через KUBECONFIG в local-exec, чтобы контекст гарантированно не улетел в kubeconfig другой машины."
  type        = string
  default     = "~/.kube/config"
}
