# terraform-laba

Домашній GitOps-стенд на k3d: Terraform піднімає кластер і голий ArgoCD,
далі **все інше** — оператори, застосунки, секрети, роутинг —
розкочується самим ArgoCD за паттерном app-of-apps. Після `terraform apply`
в `01-platform` руками в кластер більше нічого не накочується.

## Архітектура

```
Terraform (00-cluster → 01-platform → 02-observability)
  │
  ├─ k3d: 1 server + 2 agent
  ├─ helm_release "argocd"  (той самий паттерн, що і в проді — не argocd install/kubectl apply)
  └─ Application "x-system" ──────────────────────────────────┐
                                                                │ ArgoCD з цієї точки сам
                                                                │ веде весь кластер
                                                                ▼
                                              gitops/x-system (app-of-apps)
                                              один файл apps/*.yaml = одна ArgoCD Application
        ┌──────────────┬───────────────┬───────────────┬──────────────┬─────────────────┐
        │              │               │               │              │                 │
     Traefik        Vault + ESO   kube-prometheus-   ECK operator   postgres-operator   ARC
   (Gateway API,    (джерело       stack              + elastic-     (CrunchyData)      (controller +
   HTTPRoute з      секретів      (Prometheus/         stack chart                       runner-set,
   gitops/routes)   для всього    Alertmanager/         (Elasticsearch                     dind, self-
                    іншого)       Grafana)              + Kibana) +                       hosted GH
                                                         Fluent Bit                        Actions runners)
                                                                                              │
                                                                                    ┌─────────┴─────────┐
                                                                                    │   petclinic +      │
                                                                                    │   petclinic-db      │
                                                                                    │   (PostgresCluster) │
                                                                                    └─────────────────────┘

Зовні: Cloudflare Tunnel (cloudflared, звичайний Deployment з Terraform) →
Traefik Gateway → HTTPRoute на конкретний сервіс. TLS термінується на
межі Cloudflare, всередині кластера все по HTTP. Детальніше — розділ
"Мережа" нижче.
```

Terraform у три шари піднімає k3d-кластер, ставить ArgoCD і створює
єдиний об'єкт `Application "x-system"`, який дивиться на
`gitops/x-system` в цьому ж репозиторії. Далі `gitops/x-system` рендерить
по одній ArgoCD Application на кожен файл у `gitops/x-system/apps/*.yaml`
(шаблон — `templates/applications.yaml`) — щоб додати новий сервіс у
кластер, достатньо покласти туди новий файл, більше нічого не чіпаючи.

Секрети ніде не зберігаються в git: єдине джерело правди для
рантайм-секретів — Vault (`vault.vault.svc.cluster.local`, standalone-режим,
не dev), з якого External Secrets Operator (ESO) синкає їх у звичайні
Kubernetes Secret'и через `ClusterSecretStore vault-backend`
(`gitops/manifests/cluster-secret-store.yaml`), автентифікація — k8s auth
backend у Vault (`terraform/01-platform/vault-auth.tf`), не статичний
токен.

## Структура репозиторію

```
terraform/
  00-cluster/         k3d cluster (1 server + 2 agent)
  01-platform/         ArgoCD, Cloudflare Tunnel/DNS, Vault k8s-auth backend, bootstrap Application "x-system"
  02-observability/    Grafana-організація/дашборди/алерти під petclinic (провайдер grafana, не helm-values)

gitops/
  x-system/            app-of-apps: apps/*.yaml -> одна ArgoCD Application на файл
  charts/               власні Helm-чарти (petclinic, petclinic-db, elastic-stack, arc-runner-set)
  manifests/            плоскі YAML-маніфести (ClusterSecretStore, bootstrap-секрети) — синкаються як є, без Helm
  routes/                HTTPRoute (Gateway API) на все, що стирчить назовні
  vendor/                вендорені CRD-бандли (Gateway API)
```

## Компоненти

**Vault + External Secrets Operator.** Vault — єдине джерело правди
для секретів застосунків (KV v2, mount `secret`). ESO автентифікується у
Vault через Kubernetes auth backend (роль `eso`, лише `read` на
`secret/data/*`), а не токеном. Усі `ExternalSecret` у репозиторії читають
саме звідти: креди Postgres для PetClinic, R2-креди для бекапів, admin-креди
Grafana, GitHub App для ARC.

**Traefik + Gateway API.** Замість класичного Ingress — `GatewayClass`/
`Gateway`, які сам чарт Traefik створює за замовчуванням, і `HTTPRoute` у
`gitops/routes/*.yaml` на кожен зовнішній сервіс. Зовні — Cloudflare
Tunnel (`cloudflared`, звичайний Deployment на 2 репліки, заведений Terraform'ом
у `01-platform`, не через GitOps — це найперший компонент, який
має бути живий ще до того, як ArgoCD взагалі здатен щось показати
назовні). Повна схема руху запиту — розділ "Мережа" нижче.

**kube-prometheus-stack + Grafana.** Prometheus + Alertmanager + Grafana
одним чартом. Окрема Grafana-організація `petclinic`
(`terraform/02-observability`, провайдер `grafana`, не helm-values) зі своїм
datasource, папкою алертів і notification policy. `ServiceMonitor` на
PetClinic скрейпить `/actuator/prometheus` кожні 15с. Дашборд
`PetClinic - Application Overview` — 8 реальних панелей (RPS за статусами,
error rate, середня та P95-латентність, JVM heap, GC pause rate, CPU,
HikariCP connections), не дефолтний cluster-overview. Алерт
`PetClinicHighErrorRate` (будь-які 5xx за 5 хвилин, `for: 1m`) — демонструється
через вбудований у PetClinic пункт `/oups`, який завжди кидає 500.

**Elastic stack (логи).** ECK-оператор + `Elasticsearch` (2 ноди після
недавнього фіксу жовтого health, див. нижче) + `Kibana` — обидва ресурси живуть
в одному чарті `elastic-stack`, бо Kibana посилається на Elasticsearch
через `elasticsearchRef` і отримує від ECK креди/CA автоматично, без
ручних секретів. Доставка логів — Fluent Bit (DaemonSet), а не альтернативи:

  - *застосунок пише в ES сам (клієнтська бібліотека)* — відхилили: це
    прив'язує застосунок до доступності ES синхронно (недоступний ES —
    зависає або втрачає запити застосунку), плюс кожному сервісу довелося
    б самому вирішувати буферизацію/бекпрешер;
  - *сайдкар на под* — відхилили: N подів = N додаткових контейнерів,
    витрата ресурсів зростає лінійно з масштабуванням застосунку, а
    конфіг парсингу/роутингу логів розмазаний по кожному деплойменту замість
    одного місця;
  - *node-level колектор (обрано)* — Fluent Bit як DaemonSet читає
    `/var/log/containers` незалежно від застосунку: застосунок просто
    пише в stdout, падає/гальмує ES — губиться в найгіршому разі
    буфер Fluent Bit, а не сам сервіс. Один под на ноду замість одного на
    под, конфіг (парсинг Java-стектрейсів в одну подію, роутинг за
    namespace у свій індекс) в одному місці.

  Fluent Bit пересобирає багаторядкові Java-стектрейси в одну
  log-подію і розводить логи по двох індексах: `petclinic-logs` (тільки
  namespace `petclinic`) та `k8s-logs` (все інше).

**Reloader.** `watchGlobally: true`, але реально смикає лише те, що явно
підписалось анотацією `reloader.stakater.com/auto: "true"` — зараз це
Deployment `petclinic`, який читає `POSTGRES_URL/USER/PASS` із секрету,
що оновлюється ESO з Vault кожні 30с. Без Reloader под продовжив би
працювати зі старим значенням до ручного рестарту; перевірено вручну —
патч секрету дійсно тригерить rolling restart пода.

**PetClinic + БД.** Демо-застосунок — форк Spring PetClinic (вихідний код і CI
окремо, в [bohdan-ihnatenko/spring-petclinic](https://github.com/bohdan-ihnatenko/spring-petclinic),
цей репозиторій відповідає лише за інфраструктуру та деплой). БД — не
голий Postgres у Deployment+PVC, а `PostgresCluster` через CrunchyData
Postgres Operator (PGO), одна репліка інстансу, бекапи (pgBackRest) йдуть
у Cloudflare R2. І JDBC-креди застосунку, і креди R2 для бекапів приходять
через `ExternalSecret` з Vault — ніде не захардкоджені і не лежать у
Terraform-змінних.

**CI/CD (GitHub Actions, у репозиторії spring-petclinic).** `ci.yaml`:
тести → збірка jar → `docker/build-push-action` пушить образ у Docker Hub з
тегом `${GITHUB_SHA::7}` → клонує цей репозиторій, править `tag:` у
`gitops/charts/petclinic/values.yaml` і комітить/пушить назад (git
write-back). ArgoCD бачить новий коміт у `main` і сам розкочує образ —
без прямого `kubectl apply`/`helm upgrade` з CI.

**ArgoCD Image Updater vs git write-back.** Обидва вирішують одну й ту саму
задачу — оновлення тегу образу — і конфліктують, якщо запущені на одному
Application одночасно (хто останній написав у git/застосував у кластер,
той і виграв наступний цикл). Для PetClinic обрано git write-back з CI, а
не Image Updater: тег версіонується явним комітом, а не polling'ом
реєстру образів, тому вся історія деплоїв видна як звичайні коміти в
цьому репозиторії, без окремого логу в самого Image Updater. **Чесно:**
Image Updater в кластері не розгорнутий взагалі — зроблено лише сам вибір
підходу і обґрунтування, а не обидва варіанти пліч-о-пліч.

**Self-hosted runners (ARC).** `build-and-deploy` в CI крутиться на
`arc-runner-set`, а не `ubuntu-latest`: `gitops/x-system/apps/arc-controller.yaml`
ставить сам контролер (`gha-runner-scale-set-controller`, ns
`arc-systems`), `gitops/charts/arc-runner-set` — обгортка над офіційним
чартом `gha-runner-scale-set` (ns `arc-runners`) у dind-режимі (потрібен
реальний `docker build`), з `ExternalSecret` для GitHub App у тому ж
чарті/Application, щоб не ловити гонку між namespace і секретом,
який має в нього лягти. GitHub App заведено вручну (Developer
settings → GitHub Apps, права Actions: Read-only + Administration:
Read and write) — Terraform'ом це не автоматизується, креди (app-id,
installation-id, private-key) лежать у Vault (`secret/arc/github-app`).

## Мережа: Cloudflare Tunnel → Gateway API

Ключовий момент тут не "які є компоненти", а напрямок ініціації з'єднання:
**cloudflared сам виходить назовні першим**, тому на кластері немає жодного
відкритого вхідного порту — фаєрвол/NAT/публічна IP не потрібні. Cloudflare
використовує той самий вихідний тунель, щоб занести вхідний HTTPS-запит
усередину, а Traefik далі маршрутизує його виключно за заголовком `Host`.

```
Браузер
  │  1. https://*.hydranoid.site (TLS)
  ▼
Cloudflare Edge ── TLS термінується тут
  ▲                                     │
  │ 2. вихідний тунель                  │ 3. той самий тунель заносить
  │    ініціює cloudflared               │    HTTPS-запит усередину
  │    (вхідних портів у кластері нема)  │
  │                                      ▼
┌──────────────────────────── k3d кластер ─────────────────────────────┐
│                                                                        │
│  cloudflared (Deployment ×2, ns cloudflared)                          │
│     │ 4. plain HTTP :80                                               │
│     ▼                                                                  │
│  Traefik — Svc traefik-gateway (ns traefik)                           │
│  GatewayClass traefik / Gateway traefik-gateway                       │
│  HTTPRoute матчить заголовок Host                                     │
│     │                                                                   │
│     ├─ argocd.hydranoid.site    → argocd-server (ns argocd)           │
│     ├─ petclinic.hydranoid.site → petclinic (ns petclinic)            │
│     ├─ grafana.hydranoid.site   → kube-prometheus-stack-grafana (ns monitoring)
│     ├─ kibana.hydranoid.site    → kibana-kb-http (ns logging)         │
│     └─ vault.hydranoid.site     → vault (ns vault)                    │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

П'ять зовнішніх хостів — п'ять незалежних `HTTPRoute` у `gitops/routes/*.yaml`,
один спільний `Gateway`. Усередині кластера — всюди plain HTTP, жодного TLS
між подами (див. розділ "Що було б інакше" нижче про наслідки цього рішення).

## Доступ

| Сервіс | URL |
|---|---|
| ArgoCD | https://argocd.hydranoid.site |
| PetClinic | https://petclinic.hydranoid.site |
| Grafana | https://grafana.hydranoid.site |
| Kibana | https://kibana.hydranoid.site |
| Vault | https://vault.hydranoid.site |

Паролі — у Vault (`secret/argocd`, `secret/grafana` тощо), не в цьому файлі.

## Що ламалося і як лагодили

- **Elasticsearch вічний `yellow` / ArgoCD вічний `Progressing`.**
  `nodeSets.count: 1` — репліці фізично нема де бути: ES не селить репліку
  на ту ж саму ES-ноду, що і primary, скільки б k8s-нод у кластері не було.
  ArgoCD агрегує health Application із health кожного ресурсу, а
  вбудований health-check для CRD `Elasticsearch` мапить не-`green` у
  `Progressing`, а не в `Degraded` — тож це тягнулося нескінченно, не
  будучи при цьому поломкою. Раз у кластері реально є вільна k8s-нода
  під другу ES-ноду — підняли `count: 2`, кластер став `green`,
  `APP HEALTH` в ArgoCD сам прийшов у `Healthy`.
- **CrashLoopBackOff всередині `dind`-раннерів ARC при реальному `docker build`.**
  Офіційний чарт `gha-runner-scale-set` хардкодить контейнер `dind`
  цілком у `_helpers.tpl` — додати туди `--mtu` через `values.yaml`
  не можна. Вирішено PostSync-хуком (`gitops/charts/arc-runner-set`), який
  JSON-патчем дописує `--mtu=1400` в args `dind` після кожного sync; в
  Application виставлено `ignoreDifferences` на цей шлях, інакше `selfHeal`
  відкочував би патч на кожній звірці.
- **`AutoscalingListener` ARC вічно `OutOfSync` в ArgoCD.** Контролер ARC
  створює `AutoscalingListener` та його `Role`/`RoleBinding` в рантаймі (не
  через Helm/git), але копіює на них лейбл `argocd.argoproj.io/instance`
  від батька — ArgoCD приймає їх за свої, але зайві. Перемкнули
  `application.resourceTrackingMethod` ArgoCD на `annotation+label`
  (офіційний механізм під цей клас проблем): контролери на кшталт ARC
  копіюють лейбли, але не довільні анотації, тобто owner-анотацію
  дочірні об'єкти не успадкують. На `arc-runner-set` додатково
  `prune: false` — інакше живий listener видалявся б на кожному auto-sync і
  пересоздавався контролером по колу.
- **`PostgresCluster` не підхоплював креди S3 для pgBackRest.** Поле
  `repos[].s3.credentials` у CRD `PostgresCluster` не існує
  (перевірено за схемою CRD postgres-operator v6.0.3) — structural schema
  мовчки відкидає зайві поля при apply, без помилки. Правильний шлях —
  `backups.pgbackrest.configuration[].secret` з файлом `s3.conf` всередині
  секрету, який збирає ESO через `target.template`.
- **Grafana-панелі з `histogram_quantile()` (P95-латентність) були порожні.**
  Micrometer за замовчуванням не генерує histogram-бакети. Потрібна властивість —
  `management.metrics.distribution.percentiles-histogram.http.server.requests`;
  дефіс всередині `percentiles-histogram` в env-змінній за правилами relaxed
  binding Spring Boot **видаляється**, а не замінюється на підкреслення —
  якщо поставити `PERCENTILESHISTOGRAM` разом (як у правильному варіанті)
  vs `PERCENTILES_HISTOGRAM` (з підкресленням), друге читається як два
  різні сегменти шляху, потрапляє в іншу реальну властивість і валить
  контейнер на старті з `ConversionFailedException`.
- **Kibana не піднімалася на дефолтних ресурсах чарта.** Бутстрап цієї
  версії Kibana піднімає 203 плагіни; на 200m/500m CPU і 512Mi/1Gi memory
  контейнер або не вкладався в пам'ять (OOMKilled), або не встигав
  стартувати до спрацювання liveness-проби. Підняли ліміти.
- **CRD великих операторів (ECK, postgres-operator, kube-prometheus-stack,
  ARC, Gateway API) не ставилися звичайним `kubectl apply`.** Впиралися в
  ліміт 262144 байт анотації `last-applied-configuration` при client-side
  apply. Всюди, де це актуально, у Application виставлено
  `syncOptions: [ServerSideApply=true]`.

## Що було б інакше в реальному (не-локальному) середовищі

- **Одна нода Postgres, одна репліка Vault.** Тут це свідомий
  лабораторний масштаб. У проді — Postgres з реальним failover (PGO це
  вміє з коробки, тут просто не увімкнено), Vault в HA-режимі з auto-unseal
  через хмарний KMS замість файлового storage і `vault-init.json` з
  unseal-ключами на диску поруч із репозиторієм.
- **Bootstrap-секрети (GitHub PAT для доступу ArgoCD до репозиторію,
  Cloudflare tunnel token, R2 API-ключі) зараз живуть у `terraform.tfvars` і
  Terraform state, а не у Vault** — курка-і-яйце: Vault ще не піднятий,
  коли ці секрети потрібні вперше. У проді це вирішується окремим
  secrets-бекендом саме для бутстрапу (наприклад, зашифрований
  remote state + зовнішній secrets manager), а не файлами на диску
  розробника.
- **`dind` в ARC-раннерах потребує `privileged: true`** (і sysctl-контейнер
  теж privileged, руками піднімає `vm.max_map_count` для Elasticsearch).
  Нормально для домашньої лаби на одній машині, неприпустимо на
  реальному/шареному кластері — там потрібен або DaemonSet, що налаштовує
  sysctl на нодах заздалегідь, або провіжинінг-інструмент самої ноди, а для
  докер-збірок — щось на кшталт rootless BuildKit замість dind.
- **Весь трафік всередині кластера — plain HTTP**, TLS тільки на межі
  Cloudflare (див. розділ "Мережа" вище). Для лаби це ок (кластер —
  довірений периметр), у реальному середовищі — internal mTLS між
  сервісами (cert-manager + service mesh або аналог), а не голий HTTP до
  бекенда за Gateway.
- **Resource requests/limits всюди підібрані на око під один ноутбук**, не
  за реальним навантаженням — у проді це окрема робота з профілюванням і
  load-тестами, а не константи в values.yaml.
- **Image Updater vs git write-back — вибір задокументовано, але не
  реалізовано альтернативний шлях повністю** (див. секцію CI/CD вище). У
  реальному проєкті це означало б фактично розгорнутий і
  сконфігурований Image Updater (або його відсутність), а не просто
  обґрунтування в README.
