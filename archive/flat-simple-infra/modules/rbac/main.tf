resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = var.principal_id
}
resource "azurerm_role_assignment" "sa_contrib" {
  scope                = var.sa_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_id
}
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.kv_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.principal_id
}
