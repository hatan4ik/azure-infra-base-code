resource "azurerm_resource_group" "tfstate" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                     = var.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

resource "azurerm_key_vault" "main" {
  name                       = var.key_vault_name
  location                   = azurerm_resource_group.tfstate.location
  resource_group_name        = azurerm_resource_group.tfstate.name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = var.kv_retention_days
  purge_protection_enabled   = true
  enable_rbac_authorization  = true
  public_network_access_enabled = var.kv_public_network_enabled
  tags                       = var.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_name
  location            = azurerm_resource_group.tfstate.location
  resource_group_name = azurerm_resource_group.tfstate.name
  sku                 = var.log_analytics_sku
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
  sku                 = var.acr_sku
  admin_enabled       = false
  public_network_access_enabled = var.acr_public_network_enabled
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "kv" {
  name                       = "ds-kv"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "sa" {
  name                       = "ds-sa"
  target_resource_id         = azurerm_storage_account.tfstate.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "ds-acr"
  target_resource_id         = azurerm_container_registry.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_role_assignment" "mi_storage" {
  count                = var.managed_identity_principal_id != null ? 1 : 0
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_role_assignment" "mi_kv" {
  count                = var.managed_identity_principal_id != null ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_role_assignment" "mi_acr" {
  count                = var.managed_identity_principal_id != null ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = var.managed_identity_principal_id
}
