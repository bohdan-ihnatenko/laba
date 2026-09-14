output "cluster_name" {
  value = var.cluster_name
}

output "kube_context" {
  value = "k3d-${var.cluster_name}"
}
