terraform {
  required_version = ">= 1.7"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0" # проверьте актуальную мажорную версию в registry.terraform.io перед init
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0" # проверьте актуальную: registry.terraform.io/providers/hashicorp/vault
    }
  }
}
