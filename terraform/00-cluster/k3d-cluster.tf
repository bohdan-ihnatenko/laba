locals {
  remote_api_flags = var.remote_api_host != "" ? "--api-port \"${var.remote_api_host}:6550\" --k3s-arg \"--tls-san=${var.remote_api_host}@server:0\"" : ""

  docker_env     = var.remote_docker_host != "" ? { DOCKER_HOST = var.remote_docker_host } : {}
  kubeconfig_env = { KUBECONFIG = pathexpand(var.kubeconfig_path) }
}

resource "terraform_data" "k3d_cluster" {
  # Порядок важен: destroy-провижнер ниже читает эти значения только через
  # self.triggers_replace[...], потому что Terraform запрещает destroy-time
  # provisioner'ам ссылаться на var./local. напрямую (только self, count.index,
  # each.key). Индекс [3] оборачиваем в try(), потому что у ресурса, созданного
  # ДО того, как в этот список добавили 4-й элемент, в стейте лежит массив
  # только из 3 элементов — при destroy такого "старого" инстанса self всё ещё
  # содержит старые 3 значения, и try() подстраховывает от "index out of range".
  triggers_replace = [
    var.cluster_name,                # self.triggers_replace[0]
    var.remote_docker_host,          # self.triggers_replace[1]
    var.remote_api_host,             # self.triggers_replace[2]
    pathexpand(var.kubeconfig_path), # self.triggers_replace[3]
  ]

  provisioner "local-exec" {
    environment = merge(local.docker_env, local.kubeconfig_env)
    command     = <<-EOT
      k3d cluster create ${var.cluster_name} \
        --servers 1 \
        --agents 2 \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --k3s-arg "--disable=traefik@server:0" \
        --kubeconfig-update-default=true \
        --kubeconfig-switch-context=true \
        ${local.remote_api_flags} \
        --wait
    EOT
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      DOCKER_HOST = self.triggers_replace[1]
      KUBECONFIG  = try(self.triggers_replace[3], "")
    }
    command = "k3d cluster delete ${self.triggers_replace[0]}"
  }
}
