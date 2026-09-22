# Алерты про состояние подов в кластере в целом, а не про конкретное
# приложение (см. alerts-petclinic.tf для 5xx PetClinic) - отдельная папка
# и rule group, потому что это про здоровье инфраструктуры, а не одного
# сервиса. Датасорс и Slack-контакт переиспользуем те же, что и в
# organization.tf/alerts-petclinic.tf - в этой лабе один Prometheus на
# весь кластер (в т.ч. kube-state-metrics/cAdvisor из kube-prometheus-stack)
# и один канал на всё, разводить по разным адресатам смысла пока нет.

resource "grafana_folder" "kube_alerts" {
  org_id = grafana_organization.petclinic.id
  title  = "Kubernetes Alerts"
  uid    = "kube-alerts"
}

resource "grafana_rule_group" "kube" {
  org_id           = grafana_organization.petclinic.id
  name             = "kube-rules"
  folder_uid       = grafana_folder.kube_alerts.uid
  interval_seconds = 60

  # Под часто рестартует (CrashLoopBackOff и похожее). increase() за 15
  # минут, а не текущее значение kube_pod_container_status_restarts_total -
  # это счётчик, который растёт, пока жив конкретный под, но обнуляется при
  # его пересоздании; важна скорость набора рестартов за окно, а не
  # абсолютное число от непредсказуемого момента отсчёта.
  rule {
    name           = "KubePodRestartsHigh"
    for            = "0s"
    condition      = "C"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary = "Под {{ $labels.namespace }}/{{ $labels.pod }} перезапускался больше 2 раз за последние 15 минут"
    }

    labels = {
      severity = "warning"
    }

    data {
      ref_id     = "A"
      query_type = ""

      relative_time_range {
        from = 900
        to   = 0
      }

      datasource_uid = grafana_data_source.petclinic_prometheus.uid
      model = jsonencode({
        expr          = "sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total[15m]))"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "A"
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        expression = "A"
        reducer    = "last"
        refId      = "B"
        type       = "reduce"
      })
    }

    data {
      ref_id = "C"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        expression = "B"
        type       = "threshold"
        refId      = "C"
        conditions = [
          {
            evaluator = {
              params = [2]
              type   = "gt"
            }
            operator = { type = "and" }
            query    = { params = ["B"] }
            reducer  = { params = [], type = "last" }
            type     = "query"
          }
        ]
      })
    }
  }

  # Под застрял в Pending дольше 5 минут (for задан на самом правиле, не в
  # запросе) - типичные причины: не хватает ресурсов на нодах, PVC не
  # забиндился, нет ноды под нужный selector/taint. kube_pod_status_phase -
  # метрика per (pod, phase) со значением 0/1, фильтруем именно
  # phase="Pending".
  rule {
    name           = "KubePodPending"
    for            = "5m"
    condition      = "C"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary = "Под {{ $labels.namespace }}/{{ $labels.pod }} в статусе Pending дольше 5 минут"
    }

    labels = {
      severity = "warning"
    }

    data {
      ref_id     = "A"
      query_type = ""

      relative_time_range {
        from = 300
        to   = 0
      }

      datasource_uid = grafana_data_source.petclinic_prometheus.uid
      model = jsonencode({
        expr          = "sum by (namespace, pod) (kube_pod_status_phase{phase=\"Pending\"})"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "A"
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 300
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        expression = "A"
        reducer    = "last"
        refId      = "B"
        type       = "reduce"
      })
    }

    data {
      ref_id = "C"
      relative_time_range {
        from = 300
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        expression = "B"
        type       = "threshold"
        refId      = "C"
        conditions = [
          {
            evaluator = {
              params = [0]
              type   = "gt"
            }
            operator = { type = "and" }
            query    = { params = ["B"] }
            reducer  = { params = [], type = "last" }
            type     = "query"
          }
        ]
      })
    }
  }

  depends_on = [grafana_data_source.petclinic_prometheus]
}
