resource "random_string" "suffix" { length = 6 special = false upper = false }
resource "azurerm_container_registry" "acr" {
  name                          = "${var.prefix}acr${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  tags                          = var.tags
}
