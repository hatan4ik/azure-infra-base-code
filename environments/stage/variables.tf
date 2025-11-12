variable "rg_name"    { type=string }
variable "vnet_cidr"  { type=list(string) }
variable "subnets"    { type=map(object({ cidr=string })) }
variable "nat_gateway"{ type=object({ enabled=bool }) }
variable "vm_size"    { type=string }
variable "vm_count"   { type=number }
variable "acr_sku"    { type=string }
