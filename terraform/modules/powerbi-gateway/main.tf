resource "azurerm_resource_group" "powerbi" {
  count    = var.enable_gateway ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_provider_registration" "powerplatform" {
  count = var.enable_gateway ? 1 : 0
  name  = "Microsoft.PowerPlatform"
}

resource "azapi_resource" "vnet_gateway" {
  count     = var.enable_gateway ? 1 : 0
  type      = "Microsoft.PowerPlatform/vnetGateways@2020-10-30-preview"
  name      = var.gateway_name
  location  = var.location
  parent_id = azurerm_resource_group.powerbi[0].id
  tags      = var.tags

  body = jsonencode({
    properties = {
      virtualNetwork = {
        id = var.vnet_id
      }
      subnet = {
        id = var.subnet_id
      }
      associatedEnvironments = [
        for env_id in var.environment_ids : {
          id = env_id
        }
      ]
    }
  })

  depends_on = [azurerm_resource_provider_registration.powerplatform]
}
