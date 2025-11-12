output "gateway_id" {
  value = var.enable_gateway ? azapi_resource.vnet_gateway[0].id : null
}

output "resource_group_name" {
  value = var.enable_gateway ? azurerm_resource_group.powerbi[0].name : null
}
