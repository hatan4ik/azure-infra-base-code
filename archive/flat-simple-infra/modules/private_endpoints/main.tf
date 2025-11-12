resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.plink_subnet_id
  private_service_connection {
    name                           = "kv-conn"
    private_connection_resource_id = var.kv_id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  tags = var.tags
}
resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
}
resource "azurerm_private_dns_zone_virtual_network_link" "kv_link" {
  name = "kv-link"
  resource_group_name = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id = var.vnet_id
}
resource "azurerm_private_dns_a_record" "kv_a" {
  name = var.kv_name
  zone_name = azurerm_private_dns_zone.kv.name
  resource_group_name = var.resource_group_name
  ttl = 300
  records = [azurerm_private_endpoint.kv.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.plink_subnet_id
  private_service_connection {
    name                           = "blob-conn"
    private_connection_resource_id = var.sa_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  tags = var.tags
}
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
}
resource "azurerm_private_dns_zone_virtual_network_link" "blob_link" {
  name = "blob-link"
  resource_group_name = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id = var.vnet_id
}
resource "azurerm_private_dns_a_record" "blob_a" {
  name = var.sa_name
  zone_name = azurerm_private_dns_zone.blob.name
  resource_group_name = var.resource_group_name
  ttl = 300
  records = [azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_endpoint" "acr" {
  name                = "pe-acr"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.plink_subnet_id
  private_service_connection {
    name                           = "acr-conn"
    private_connection_resource_id = var.acr_id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }
  tags = var.tags
}
resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
}
resource "azurerm_private_dns_zone_virtual_network_link" "acr_link" {
  name = "acr-link"
  resource_group_name = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id = var.vnet_id
}
resource "azurerm_private_dns_a_record" "acr_a" {
  name = var.acr_name
  zone_name = azurerm_private_dns_zone.acr.name
  resource_group_name = var.resource_group_name
  ttl = 300
  records = [azurerm_private_endpoint.acr.private_service_connection[0].private_ip_address]
}
