terraform {
  required_providers { azurerm = { source="hashicorp/azurerm" version="~>3.116" } }
}
provider "azurerm" { features {} }
variable "location" { type=string, default="eastus" }
variable "rg_name" { type=string, default="rg-tfstate" }
variable "sa_name" { type=string, default="tfstateglobal001" }
resource "azurerm_resource_group" "rg" { name=var.rg_name location=var.location }
resource "azurerm_storage_account" "sa" {
  name=var.sa_name resource_group_name=azurerm_resource_group.rg.name location=var.location
  account_tier="Standard" account_replication_type="LRS" allow_nested_items_to_be_public=false
}
resource "azurerm_storage_container" "state" { name="tfstate" storage_account_name=azurerm_storage_account.sa.name container_access_type="private" }
