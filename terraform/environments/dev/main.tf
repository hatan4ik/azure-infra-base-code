terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.10"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azapi" {}

locals {
  environment = "dev"
  tags = {
    Environment  = "dev"
    ManagedBy    = "Terraform"
    Project      = "example-platform"
    BusinessUnit = "core"
    Owner        = "platform-team"
  }
}

# Stage 0: Managed Identity (OIDC)
module "managed_identity" {
  source = "../../modules/managed-identity"

  resource_group_name        = var.mi_resource_group_name
  location                   = var.location
  identity_name              = var.mi_name
  subscription_id            = "/subscriptions/${var.subscription_id}"
  federated_credential_name  = "ado-federated-credential"
  oidc_issuer                = var.oidc_issuer
  oidc_subject               = var.oidc_subject
  tags                       = local.tags
}

# Stage 1: Bootstrap
module "bootstrap" {
  source = "../../modules/bootstrap"

  resource_group_name           = var.bootstrap_resource_group_name
  location                      = var.location
  storage_account_name          = var.tfstate_storage_account_name
  container_name                = var.tfstate_container_name
  key_vault_name                = var.key_vault_name
  tenant_id                     = var.tenant_id
  kv_retention_days             = var.kv_retention_days
  kv_public_network_enabled     = var.kv_public_network_enabled
  log_analytics_name            = var.log_analytics_name
  log_analytics_sku             = var.log_analytics_sku
  acr_name                      = var.acr_name
  acr_sku                       = var.acr_sku
  acr_public_network_enabled    = var.acr_public_network_enabled
  managed_identity_principal_id = module.managed_identity.principal_id
  tags                          = local.tags

  depends_on = [module.managed_identity]
}

# Stage 2: Network
module "network" {
  source = "../../modules/network"

  resource_group_name      = var.network_resource_group_name
  location                 = var.location
  vnet_name                = var.vnet_name
  vnet_cidr                = var.vnet_cidr
  subnet_workloads_name    = var.subnet_workloads_name
  subnet_workloads_cidr    = var.subnet_workloads_cidr
  subnet_pe_name           = var.subnet_pe_name
  subnet_pe_cidr           = var.subnet_pe_cidr
  enable_powerbi_gateway   = var.enable_powerbi_gateway
  subnet_pbi_name          = var.subnet_pbi_name
  subnet_pbi_cidr          = var.subnet_pbi_cidr
  tags                     = local.tags

  depends_on = [module.bootstrap]
}

# Stage 3: Customer Storage
module "customer_storage" {
  source = "../../modules/storage"

  resource_group_name           = var.customer_resource_group_name
  location                      = var.location
  storage_account_name          = var.customer_storage_account_name
  containers                    = var.customer_containers
  enable_private_endpoint       = var.enable_storage_private_endpoint
  network_resource_group_name   = module.network.resource_group_name
  subnet_pe_id                  = module.network.subnet_pe_id
  dns_zone_blob_id              = module.network.dns_zone_blob_id
  dns_zone_dfs_id               = module.network.dns_zone_dfs_id
  log_analytics_workspace_id    = module.bootstrap.log_analytics_workspace_id
  managed_identity_principal_id = module.managed_identity.principal_id
  tags                          = local.tags

  depends_on = [module.network]
}

# Stage 4: Power BI Gateway (Optional)
module "powerbi_gateway" {
  source = "../../modules/powerbi-gateway"

  enable_gateway      = var.enable_powerbi_gateway
  resource_group_name = var.powerbi_resource_group_name
  location            = var.location
  gateway_name        = var.powerbi_gateway_name
  vnet_id             = module.network.vnet_id
  subnet_id           = module.network.subnet_pbi_id
  environment_ids     = var.powerbi_environment_ids
  tags                = local.tags

  depends_on = [module.network]
}
