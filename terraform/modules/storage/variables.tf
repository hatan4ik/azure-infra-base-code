variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "containers" {
  type    = list(string)
  default = []
}

variable "enable_private_endpoint" {
  type    = bool
  default = true
}

variable "network_resource_group_name" {
  type    = string
  default = ""
}

variable "subnet_pe_id" {
  type    = string
  default = ""
}

variable "dns_zone_blob_id" {
  type    = string
  default = ""
}

variable "dns_zone_dfs_id" {
  type    = string
  default = ""
}

variable "log_analytics_workspace_id" {
  type    = string
  default = null
}

variable "managed_identity_principal_id" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
