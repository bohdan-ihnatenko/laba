output "petclinic_org_id" {
  value = grafana_organization.petclinic.id
}

output "petclinic_dashboard_url" {
  value = "${var.grafana_url}/d/petclinic-overview"
}
