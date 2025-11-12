variable "env" { type = string }
variable "location" { type = string, default = "eastus" }
variable "prefix"   { type = string, default = "evk" }
variable "tags" { type = map(string) default = { owner = "ccoe", app = "code-runner" } }
variable "vnet_cidr"          { type = string, default = "10.70.0.0/16" }
variable "subnet_agents_cidr" { type = string, default = "10.70.1.0/24" }
variable "subnet_plink_cidr"  { type = string, default = "10.70.2.0/24" }
variable "vmss_capacity" { type = number, default = 2 }
variable "vmss_sku"      { type = string, default = "Standard_D2s_v5" }
variable "kv_sku"        { type = string, default = "standard" }
variable "sa_replication" { type = string, default = "LRS" }
variable "storage_container_name" { type = string, default = "outputs" }
variable "enable_azure_firewall" { type = bool, default = false }
