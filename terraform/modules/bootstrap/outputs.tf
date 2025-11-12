output "resource_group_name" {
  value = azurerm_resource_group.tfstate.name
}

output "storage_account_id" {
  value = azurerm_storage_account.tfstate.id
}

output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "acr_id" {
  value = azurerm_container_registry.main.id
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}
