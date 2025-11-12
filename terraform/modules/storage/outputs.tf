output "storage_account_id" {
  value = azurerm_storage_account.main.id
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "primary_dfs_endpoint" {
  value = azurerm_storage_account.main.primary_dfs_endpoint
}

output "resource_group_name" {
  value = azurerm_resource_group.storage.name
}
