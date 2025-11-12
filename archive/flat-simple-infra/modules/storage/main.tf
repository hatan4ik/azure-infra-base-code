resource "random_string" "suffix" { length = 6 special = false upper = false }
resource "azurerm_storage_account" "sa" {
  name                             = "${var.prefix}sa${random_string.suffix.result}"
  resource_group_name              = var.resource_group_name
  location                         = var.location
  account_tier                     = "Standard"
  account_replication_type         = var.replication
  public_network_access_enabled    = false
  allow_nested_items_to_be_public  = false
  tags                             = var.tags
}
resource "azurerm_storage_container" "c" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}
