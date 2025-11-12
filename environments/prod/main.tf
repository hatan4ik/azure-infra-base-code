terraform {
  backend "azurerm" {}
}

provider "azurerm" { features {} }

locals {
  environment = "prod"
  org         = "example"
  cloud_init  = templatefile("${path.module}/../../cloud-init/agents.yaml", {})
}

module "network" {
  source = "git::https://dev.azure.com/<ORG>/<PROJECT>/_git/example.network?ref=v1.0.0"
  resource_group_name = var.rg_name
  name_prefix = local.org
  workload    = "vnet"
  env         = local.environment
  vnet_cidr   = var.vnet_cidr
  subnets     = var.subnets
  nat_gateway = var.nat_gateway
}

module "keyvault" {
  source = "git::https://dev.azure.com/<ORG>/<PROJECT>/_git/example.keyvault?ref=v1.0.0"
  resource_group_name = var.rg_name
  name_prefix = local.org
  workload    = "kv"
  env         = local.environment
}

module "acr" {
  source = "git::https://dev.azure.com/<ORG>/<PROJECT>/_git/example.acr?ref=v1.0.0"
  resource_group_name = var.rg_name
  name_prefix = local.org
  workload    = "acr"
  env         = local.environment
  sku         = var.acr_sku
}

module "storage" {
  source = "git::https://dev.azure.com/<ORG>/<PROJECT>/_git/example.storage?ref=v1.0.0"
  resource_group_name = var.rg_name
  name_prefix = local.org
  workload    = "st"
  env         = local.environment
}

module "vmss_agents" {
  source = "git::https://dev.azure.com/<ORG>/<PROJECT>/_git/example.vmss-agents?ref=v1.0.0"
  resource_group_name   = var.rg_name
  name_prefix           = local.org
  workload              = "agents"
  env                   = local.environment
  subnet_id             = module.network.subnet_ids["agents"]
  instance_size         = var.vm_size
  instance_count        = var.vm_count
  custom_data_cloudinit = local.cloud_init
}

module "privatelink" {
  source = "git::https://dev.azure.com/<ORG>/<PROJECT>/_git/example.privatelink?ref=v1.0.0"
  resource_group_name   = var.rg_name
  vnet_id               = module.network.vnet_id
  privatelink_subnet_id = module.network.subnet_ids["privatelink"]
  services = {
    kv = {
      target_resource_id = module.keyvault.id
      group_ids          = ["vault"]
      dns_zone           = "privatelink.vaultcore.azure.net"
      record_name        = module.keyvault.name
    }
    acr = {
      target_resource_id = module.acr.id
      group_ids          = ["registry"]
      dns_zone           = "privatelink.azurecr.io"
      record_name        = module.acr.login_server
    }
  }
}

module "rbac" {
  source = "git::https://dev.azure.com/<ORG>/<PROJECT>/_git/example.rbac?ref=v1.0.0"
  assignments = [
    { scope_id = module.acr.id,      role_name = "AcrPull",                       principal_id = module.vmss_agents.principal_id },
    { scope_id = module.keyvault.id, role_name = "Key Vault Secrets User",        principal_id = module.vmss_agents.principal_id }
  ]
}

module "defender" {
  source = "git::https://dev.azure.com/<ORG>/<PROJECT>/_git/example.defender?ref=v1.0.0"
  enable_container_registry = true
  enable_vms                = true
  enable_appservices        = false
}

output "acr_login"     { value = module.acr.login_server }
