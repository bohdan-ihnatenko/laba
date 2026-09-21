# ArgoCD ставится тем же паттерном, что и в проде у нас — helm_release,
# а не argocd install / kubectl apply.

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.11" # проверьте актуальную версию: helm search repo argo/argo-cd -l

  values = [
    yamlencode({
      configs = {
        params = {
          # Отдаём ArgoCD по plain HTTP — TLS терминирует Cloudflare edge,
          # внутри кластера это доверенный сегмент (см. предыдущее обсуждение cert-manager).
          "server.insecure" = true
        }
        cm = {
          # По умолчанию ArgoCD определяет "своё ли это ресурс" по лейблу
          # argocd.argoproj.io/instance — и это ломается для контроллеров,
          # которые бездумно копируют ВСЕ лейблы родителя на дочерние объекты,
          # которые они создают сами в рантайме (не через Helm/git). Ровно
          # так делает actions-runner-controller: AutoscalingRunnerSet
          # (наш, из чарта gitops/charts/arc-runner-set) получает лейбл от
          # ArgoCD как положено, а вот AutoscalingListener + его Role/
          # RoleBinding, которые контроллер создаёт САМ под капотом, просто
          # наследуют лейблы родителя — включая чужой argocd.argoproj.io/
          # instance — и ArgoCD принимает их за "свои, но лишние" (OutOfSync).
          #
          # annotation+label переключает то, ЧТО ArgoCD считает источником
          # истины о владении, на аннотацию argocd.argoproj.io/tracking-id
          # (лейбл при этом всё ещё проставляется, просто для удобства
          # kubectl -l, а не для решений о синке/prune). Контроллеры вроде
          # ARC копируют labels, но не копируют произвольные annotations —
          # значит дочерние объекты аннотацию не унаследуют, и ArgoCD
          # перестанет путать их со своими. Это официальный механизм самого
          # ArgoCD именно под этот класс проблем, а не костыль с нашей стороны.
          #
          # См. https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/
          "application.resourceTrackingMethod" = "annotation+label"
        }
      }
    })
  ]

}
