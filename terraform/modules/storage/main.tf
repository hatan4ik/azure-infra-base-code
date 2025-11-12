resource "azurerm_resource_group" "storage" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.storage.name
  location                 = azurerm_resource_group.storage.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                     = var.tags
}

resource "azurerm_storage_container" "containers" {
  for_each              = toset(var.containers)
  name                  = each.value
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "blob" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "pe-${var.storage_account_name}-blob"
  location            = azurerm_resource_group.storage.location
  resource_group_name = var.network_resource_group_name
  subnet_id           = var.subnet_pe_id
  tags                = var.tags

  private_service_connection {
    name                           = "conn-${var.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.main.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "dzg-${var.storage_account_name}-blob"
    private_dns_zone_ids = [var.dns_zone_blob_id]
  }
}

resource "azurerm_private_endpoint" "dfs" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "pe-${var.storage_account_name}-dfs"
  location            = azurerm_resource_group.storage.location
  resource_group_name = var.network_resource_group_name
  subnet_id           = var.subnet_pe_id
  tags                = var.tags

  private_service_connection {
    name                           = "conn-${var.storage_account_name}-dfs"
    private_connection_resource_id = azurerm_storage_account.main.id
    is_manual_connection           = false
    subresource_names              = ["dfs"]
  }

  private_dns_zone_group {
    name                 = "dzg-${var.storage_account_name}-dfs"
    private_dns_zone_ids = [var.dns_zone_dfs_id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "ds-storage"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  metric {
    category = "Transaction"
  }
}

resource "azurerm_role_assignment" "mi_storage" {
  count                = var.managed_identity_principal_id != null ? 1 : 0
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.managed_identity_principal_id
}
