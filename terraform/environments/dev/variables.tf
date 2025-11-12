variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID"
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure region"
}

# Managed Identity
variable "mi_resource_group_name" {
  type    = string
  default = "rg-ado-wif"
}

variable "mi_name" {
  type    = string
  default = "ado-wif-mi"
}

variable "oidc_issuer" {
  type        = string
  description = "OIDC issuer URL"
}

variable "oidc_subject" {
  type        = string
  description = "OIDC subject"
}

# Bootstrap
variable "bootstrap_resource_group_name" {
  type    = string
  default = "rg-example-tfstate"
}

variable "tfstate_storage_account_name" {
  type    = string
  default = "stexampletfstate"
}

variable "tfstate_container_name" {
  type    = string
  default = "tfstate"
}

variable "key_vault_name" {
  type    = string
  default = "kv-example-platform"
}

variable "kv_retention_days" {
  type    = number
  default = 30
}

variable "kv_public_network_enabled" {
  type    = bool
  default = false
}

variable "log_analytics_name" {
  type    = string
  default = "law-example-platform"
}

variable "log_analytics_sku" {
  type    = string
  default = "PerGB2018"
}

variable "acr_name" {
  type    = string
  default = "acrexampleplatform"
}

variable "acr_sku" {
  type    = string
  default = "Premium"
}

variable "acr_public_network_enabled" {
  type    = bool
  default = false
}

# Network
variable "network_resource_group_name" {
  type    = string
  default = "rg-example-core-net"
}

variable "vnet_name" {
  type    = string
  default = "vnet-example-core"
}

variable "vnet_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "subnet_workloads_name" {
  type    = string
  default = "snet-workloads"
}

variable "subnet_workloads_cidr" {
  type    = string
  default = "10.10.0.0/24"
}

variable "subnet_pe_name" {
  type    = string
  default = "snet-private-endpoints"
}

variable "subnet_pe_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

# Customer Storage
variable "customer_resource_group_name" {
  type    = string
  default = "rg-example-data-washington"
}

variable "customer_storage_account_name" {
  type    = string
  default = "stexamplewashington"
}

variable "customer_containers" {
  type    = list(string)
  default = ["invoices", "archive"]
}

variable "enable_storage_private_endpoint" {
  type    = bool
  default = true
}

# Power BI Gateway
variable "enable_powerbi_gateway" {
  type    = bool
  default = false
}

variable "powerbi_resource_group_name" {
  type    = string
  default = "rg-example-analytics"
}

variable "powerbi_gateway_name" {
  type    = string
  default = "example-powerbi-gateway"
}

variable "subnet_pbi_name" {
  type    = string
  default = "snet-powerbi-gateway"
}

variable "subnet_pbi_cidr" {
  type    = string
  default = "10.10.3.0/27"
}

variable "powerbi_environment_ids" {
  type    = list(string)
  default = []
}
