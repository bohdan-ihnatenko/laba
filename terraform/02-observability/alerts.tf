resource "grafana_folder" "petclinic_alerts" {
  org_id = grafana_organization.petclinic.id
  title  = "PetClinic Alerts"
  uid    = "petclinic-alerts"
}

# Упрощённый contact point — без PagerDuty/Slack, как в компании (там
# modules/grafana/alerts заводит их через отдельный pagerduty-провайдер).
# Для лабы достаточно, чтобы алерт реально дошёл до встроенного Alertmanager
# Grafana и был виден на вкладке Alerting → Contact points / Notifications.
# Email тут условный — реальная доставка потребует настроенный SMTP в самой
# Grafana (сейчас не настроен), но для демонстрации "алерт сработал" в UI
# это не нужно, достаточно смотреть вкладку Alert rules → State: Firing.
resource "grafana_contact_point" "petclinic_default" {
  org_id = grafana_organization.petclinic.id
  name   = "petclinic-default"

  slack {
    url = var.slack_webhook
  }
}

resource "grafana_notification_policy" "petclinic" {
  org_id        = grafana_organization.petclinic.id
  contact_point = grafana_contact_point.petclinic_default.name
  group_by      = ["..."]

  group_wait      = "10s"
  group_interval  = "1m"
  repeat_interval = "1h"
}

# Алерт: любые 5xx-ответы PetClinic за последние 5 минут. Специально выбран
# абсолютный порог (>0), а не процент ошибок от общего трафика — так алерт
# реально можно потрогать руками на демо: у Spring PetClinic есть встроенный
# пункт меню "Error" (/oups), который намеренно бросает исключение и всегда
# отдаёт 500. Несколько раз дёрнуть его в течение ~минуты — и правило должно
# перейти в Firing (for = "1m", т.е. порог должен держаться минуту подряд).
resource "grafana_rule_group" "petclinic" {
  org_id           = grafana_organization.petclinic.id
  name             = "petclinic-rules"
  folder_uid       = grafana_folder.petclinic_alerts.uid
  interval_seconds = 60

  rule {
    name           = "PetClinicHighErrorRate"
    for            = "1m"
    condition      = "C"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary     = "PetClinic отдаёт 5xx-ответы (проверь /oups как источник демо-ошибки)"
      runbook_url = "https://github.com/bohdan-ihnatenko/laba"
      # Служебные аннотации Grafana: по ним она сама строит deep-link в
      # тайтле уведомления на конкретную панель, а не на страницу правила.
      # panelId=2 - id панели "Error rate (5xx / total)" в
      # dashboards/petclinic-overview.json; если панели в дашборде
      # переставить/удалить, id нужно свериить заново.
      __dashboardUid__ = grafana_dashboard.petclinic_overview.uid
      __panelId__       = "2"
    }

    labels = {
      severity = "critical"
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
        expr          = "sum(increase(http_server_requests_seconds_count{status=~\"5..\"}[5m]))"
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
