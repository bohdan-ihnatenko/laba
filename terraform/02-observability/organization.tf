# Отдельная Grafana-организация под демо-стенд PetClinic — так же, как в
# компании у каждого проекта/окружения своя организация со своим набором
# датасорсов (modules/grafana/organization в terragrunt-infrastructure-catalog).
# Тут сильно упрощённая версия для лабы: одна организация, один админ (тот
# же admin, что и глобальный суперадмин Grafana), один датасорс — Prometheus
# из kube-prometheus-stack этого же кластера.

resource "grafana_organization" "petclinic" {
  name         = "petclinic"
  create_users = false
  admins = ["admin@localhost"]
}

resource "grafana_data_source" "petclinic_prometheus" {
  org_id = grafana_organization.petclinic.id

  name       = "prometheus"
  type       = "prometheus"
  uid        = "petclinic-prometheus"
  url        = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
  is_default = true

  json_data_encoded = jsonencode({
    httpMethod = "POST"
  })
}
