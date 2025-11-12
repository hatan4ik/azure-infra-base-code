resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "${var.prefix}-vmss-agents"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  instances           = var.capacity
  admin_username      = "azdoagent"

  network_interface {
    name    = "nic"
    primary = true
    ip_configuration {
      name      = "ipcfg"
      primary   = true
      subnet_id = var.subnet_id
    }
  }

  os_disk { caching = "ReadWrite" storage_account_type = "Premium_LRS" }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity { type = "SystemAssigned" }

  upgrade_mode = "Automatic"

  custom_data = base64encode(file("${path.module}/files/cloud-init.yaml"))
  tags        = var.tags
}
