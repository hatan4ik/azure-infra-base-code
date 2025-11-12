output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "subnet_workloads_id" {
  value = azurerm_subnet.workloads.id
}

output "subnet_pe_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "subnet_pbi_id" {
  value = var.enable_powerbi_gateway ? azurerm_subnet.powerbi_gateway[0].id : null
}

output "dns_zone_blob_id" {
  value = azurerm_private_dns_zone.blob.id
}

output "dns_zone_dfs_id" {
  value = azurerm_private_dns_zone.dfs.id
}

output "dns_zone_vault_id" {
  value = azurerm_private_dns_zone.vault.id
}

output "dns_zone_acr_id" {
  value = azurerm_private_dns_zone.acr.id
}

output "resource_group_name" {
  value = azurerm_resource_group.network.name
}
