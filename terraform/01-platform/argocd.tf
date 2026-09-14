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
      }
    })
  ]

}
