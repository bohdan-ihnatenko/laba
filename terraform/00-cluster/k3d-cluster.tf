# Локальный k3d-кластер. Официального стабильного Terraform-провайдера под k3d
# нет (есть пара мелких community-провайдеров без гарантий), поэтому кластер
# создаётся тем же способом, каким его создали бы руками — через k3d CLI,
# обёрнутый в terraform_data + local-exec. Это осознанный компромисс, а не забытый TODO.
#
# Terraform (и сам k3d CLI) по-прежнему выполняются на этой машине — меняется
# только то, к какому Docker-движку они стучатся. Если remote_docker_host
# задан, DOCKER_HOST для local-exec указывает на удалённый движок (например,
# домашний ноут по SSH) — контейнеры кластера реально создаются там. При этом
# сам kubeconfig пишет CLI-процесс k3d, а он выполняется здесь же, на этой
# машине — но чтобы не зависеть от того, что случайно лежит в переменной
# окружения KUBECONFIG (например, если раньше кластер поднимался прямо на
# домашнем ноуте и там же гулял смерженный kubeconfig), явно фиксируем целевой
# файл через KUBECONFIG в local-exec и включаем
# --kubeconfig-update-default/--kubeconfig-switch-context — контекст
# гарантированно оказывается в kubeconfig именно этой машины.

locals {
  # Без этого k3s API слушает только на 127.0.0.1/внутреннем docker-адресе, и
  # TLS-сертификат сервера не содержит адрес удалённой машины в SAN — kubectl
  # с этой машины получит либо connection refused, либо x509: certificate is
  # valid for ..., not <remote_api_host>.
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
