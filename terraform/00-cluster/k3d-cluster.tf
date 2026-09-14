# Локальный k3d-кластер. Официального стабильного Terraform-провайдера под k3d
# нет (есть пара мелких community-провайдеров без гарантий), поэтому кластер
# создаётся тем же способом, каким его создали бы руками — через k3d CLI,
# обёрнутый в terraform_data + local-exec. Это осознанный компромисс, а не забытый TODO.

locals {
  ca_volume_flag = var.corporate_ca_cert_path != "" ? "--volume \"${var.corporate_ca_cert_path}:/etc/ssl/certs/corporate-ca.crt@all\"" : ""
}

resource "terraform_data" "k3d_cluster" {
  triggers_replace = [var.cluster_name, var.corporate_ca_cert_path]

  provisioner "local-exec" {
    command = <<-EOT
      k3d cluster create ${var.cluster_name} \
        --servers 1 \
        --agents 2 \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        ${local.ca_volume_flag} \
        --wait
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete ${self.triggers_replace[0]}"
  }
}
