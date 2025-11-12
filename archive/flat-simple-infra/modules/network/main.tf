resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = [var.vnet_cidr]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "agents" {
  name                 = "${var.prefix}-agents-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.agents_cidr]
}

resource "azurerm_subnet" "plink" {
  name                 = "${var.prefix}-plink-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.plink_cidr]
}

resource "azurerm_public_ip" "nat_ip" {
  name                = "${var.prefix}-nat-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "nat" {
  name                = "${var.prefix}-nat"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "assoc" {
  nat_gateway_id = azurerm_nat_gateway.nat.id
  public_ip_id   = azurerm_public_ip.nat_ip.id
}

resource "azurerm_subnet_nat_gateway_association" "agents_assoc" {
  subnet_id      = azurerm_subnet.agents.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}
