output "managed_identity_client_id" {
  value = module.managed_identity.client_id
}

output "managed_identity_principal_id" {
  value = module.managed_identity.principal_id
}

output "key_vault_id" {
  value = module.bootstrap.key_vault_id
}

output "acr_login_server" {
  value = module.bootstrap.acr_login_server
}

output "vnet_id" {
  value = module.network.vnet_id
}

output "customer_storage_account_name" {
  value = module.customer_storage.storage_account_name
}

output "powerbi_gateway_id" {
  value = module.powerbi_gateway.gateway_id
}
