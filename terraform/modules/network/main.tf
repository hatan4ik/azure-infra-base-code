resource "azurerm_resource_group" "network" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "workloads" {
  name                 = var.subnet_workloads_name
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_workloads_cidr]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = var.subnet_pe_name
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_pe_cidr]
}

resource "azurerm_subnet" "powerbi_gateway" {
  count                = var.enable_powerbi_gateway ? 1 : 0
  name                 = var.subnet_pbi_name
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_pbi_cidr]

  delegation {
    name = "powerplatform"
    service_delegation {
      name = "Microsoft.PowerPlatform/vnetaccesslinks"
    }
  }
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "dfs" {
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "ln-${var.vnet_name}-blob"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dfs" {
  name                  = "ln-${var.vnet_name}-dfs"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.dfs.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  name                  = "ln-${var.vnet_name}-vault"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "ln-${var.vnet_name}-acr"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = var.tags
}
