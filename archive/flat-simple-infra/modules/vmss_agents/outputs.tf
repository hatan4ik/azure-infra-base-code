output "name" { value = azurerm_linux_virtual_machine_scale_set.vmss.name }
output "identity_principal_id" { value = azurerm_linux_virtual_machine_scale_set.vmss.identity[0].principal_id }
