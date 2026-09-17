terraform {
  required_version = ">= 1.7"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0" # проверьте актуальную: registry.terraform.io/providers/grafana/grafana
    }
  }
}
