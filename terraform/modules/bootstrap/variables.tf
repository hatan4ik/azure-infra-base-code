variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "container_name" {
  type    = string
  default = "tfstate"
}

variable "key_vault_name" {
  type = string
}

variable "tenant_id" {
  type = string
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
  type = string
}

variable "log_analytics_sku" {
  type    = string
  default = "PerGB2018"
}

variable "acr_name" {
  type = string
}

variable "acr_sku" {
  type    = string
  default = "Premium"
}

variable "acr_public_network_enabled" {
  type    = bool
  default = false
}

variable "managed_identity_principal_id" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
