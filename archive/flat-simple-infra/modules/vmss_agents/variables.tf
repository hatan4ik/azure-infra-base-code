variable "prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "sku" { type = string }
variable "capacity" { type = number }
variable "tags" { type = map(string) }
