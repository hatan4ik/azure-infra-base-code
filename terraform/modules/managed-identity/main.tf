resource "azurerm_resource_group" "mi" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_user_assigned_identity" "main" {
  name                = var.identity_name
  resource_group_name = azurerm_resource_group.mi.name
  location            = azurerm_resource_group.mi.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "contributor" {
  scope                = var.subscription_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_role_assignment" "uaa" {
  scope                = var.subscription_id
  role_definition_name = "User Access Administrator"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_federated_identity_credential" "oidc" {
  name                = var.federated_credential_name
  resource_group_name = azurerm_resource_group.mi.name
  parent_id           = azurerm_user_assigned_identity.main.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer
  subject             = var.oidc_subject
}
