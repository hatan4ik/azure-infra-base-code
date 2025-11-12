variable "prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "container_name" { type = string }
variable "replication" { type = string, default = "LRS" }
variable "tags" { type = map(string) }
