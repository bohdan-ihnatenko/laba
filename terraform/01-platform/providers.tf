provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = "k3d-${var.cluster_name}"
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = "k3d-${var.cluster_name}"
  }
}


provider "vault" {
  address = var.vault_addr
  token   = var.vault_root_token
}
