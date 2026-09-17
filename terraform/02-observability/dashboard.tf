resource "grafana_folder" "petclinic" {
  org_id = grafana_organization.petclinic.id
  title  = "PetClinic"
  uid    = "petclinic"
}

resource "grafana_dashboard" "petclinic_overview" {
  org_id      = grafana_organization.petclinic.id
  folder      = grafana_folder.petclinic.uid
  config_json = file("${path.module}/dashboards/petclinic-overview.json")
  overwrite   = true
}
