terraform {
  required_version = ">= 1.7"
  # Ни одного provider-блока не нужно: terraform_data + local-exec — часть ядра Terraform.
}
