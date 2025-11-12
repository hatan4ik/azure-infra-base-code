resource "random_string" "suffix" { length = 6 special = false upper = false }
data "azurerm_client_config" "current" {}
resource "azurerm_key_vault" "kv" {
  name                          = "${var.prefix}-kv-${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.sku_name
  purge_protection_enabled      = true
  soft_delete_retention_days    = 14
  public_network_access_enabled = false
  tags                          = var.tags
}
