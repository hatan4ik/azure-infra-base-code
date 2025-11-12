output "vnet_id"          { value = azurerm_virtual_network.vnet.id }
output "vnet_name"        { value = azurerm_virtual_network.vnet.name }
output "subnet_agents_id" { value = azurerm_subnet.agents.id }
output "subnet_plink_id"  { value = azurerm_subnet.plink.id }
output "nat_public_ip"    { value = azurerm_public_ip.nat_ip.ip_address }
