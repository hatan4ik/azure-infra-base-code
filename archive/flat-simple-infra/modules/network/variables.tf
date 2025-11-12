variable "prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "vnet_cidr" { type = string }
variable "agents_cidr" { type = string }
variable "plink_cidr" { type = string }
variable "enable_azure_firewall" { type = bool, default = false }
variable "tags" { type = map(string) }
