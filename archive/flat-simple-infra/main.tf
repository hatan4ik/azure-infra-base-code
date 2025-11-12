resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = var.location
  tags     = local.common_tags
}

module "network" {
  source              = "./modules/network"
  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  vnet_cidr           = var.vnet_cidr
  agents_cidr         = var.subnet_agents_cidr
  plink_cidr          = var.subnet_plink_cidr
  enable_azure_firewall = var.enable_azure_firewall
  tags                = local.common_tags
}

module "acr" {
  source              = "./modules/acr"
  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.common_tags
}

module "storage" {
  source              = "./modules/storage"
  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  container_name      = var.storage_container_name
  replication         = var.sa_replication
  tags                = local.common_tags
}

module "keyvault" {
  source              = "./modules/keyvault"
  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = var.kv_sku
  tags                = local.common_tags
}

module "private_endpoints" {
  source              = "./modules/private_endpoints"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  vnet_id             = module.network.vnet_id
  plink_subnet_id     = module.network.subnet_plink_id
  kv_id   = module.keyvault.id
  kv_name = module.keyvault.name
  acr_id  = module.acr.id
  acr_name= module.acr.name
  sa_id   = module.storage.id
  sa_name = module.storage.name
  tags    = local.common_tags
}

module "vmss_agents" {
  source              = "./modules/vmss_agents"
  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.network.subnet_agents_id
  sku                 = var.vmss_sku
  capacity            = local.capacity
  tags                = local.common_tags
}

module "rbac" {
  source       = "./modules/rbac"
  principal_id = module.vmss_agents.identity_principal_id
  acr_id       = module.acr.id
  sa_id        = module.storage.id
  kv_id        = module.keyvault.id
}
