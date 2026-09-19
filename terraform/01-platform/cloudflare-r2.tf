# R2-бакет под офсайт-бэкапы Postgres (pgBackRest у petclinic-db).
#
# ВАЖНО про имя: ты попросил назвать бакет "cloudflare-r2-creds" — обычно
# так называют место, где лежат КРЕДЫ (ключи доступа), а не сам бакет с
# данными бэкапов. Сделал ровно как просил — если это было по инерции/
# опечатка и на самом деле хотел что-то вроде petclinic-pgbackrest-backups,
# просто скажи, переименую в одну правку.
resource "cloudflare_r2_bucket" "petclinic_backups" {
  account_id = var.cloudflare_account_id
  name       = "cloudflare-r2-backup"
}

# Terraform НЕ может создать сами S3-совместимые креды (Access Key ID /
# Secret Access Key) для R2 — у cloudflare-провайдера нет для этого ресурса
# (проверено: только cloudflare_r2_bucket и производные от бакета —
# cors/lifecycle/lock/sippy/custom_domain; отдельного "r2 access key"
# ресурса нет). Сами ключи выпускаются только вручную:
#
#   Cloudflare Dashboard → R2 → Manage R2 API Tokens → Create API Token
#   (Object Read & Write, ограничь на бакет cloudflare-r2-creds)
#   → это даст Access Key ID + Secret Access Key.
#
# Дальше кладём их в Vault (тем же паттерном, что и Grafana/Postgres):
#
#   Vault UI → Secrets → secret → создать путь petclinic/r2-backup
#   поля: access-key, secret-key — значения из созданного токена.
#
# gitops/charts/petclinic-db/templates/externalsecret-backup.yaml зеркалит
# их оттуда в K8s Secret, который читает pgBackRest.
