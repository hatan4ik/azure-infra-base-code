variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "vnet_cidr" {
  type = string
}

variable "subnet_workloads_name" {
  type    = string
  default = "snet-workloads"
}

variable "subnet_workloads_cidr" {
  type = string
}

variable "subnet_pe_name" {
  type    = string
  default = "snet-private-endpoints"
}

variable "subnet_pe_cidr" {
  type = string
}

variable "enable_powerbi_gateway" {
  type    = bool
  default = false
}

variable "subnet_pbi_name" {
  type    = string
  default = "snet-powerbi-gateway"
}

variable "subnet_pbi_cidr" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
