rg_name   = "rg-example-stage"
vnet_cidr = ["10.70.0.0/16"]
subnets = { agents={ cidr="10.70.1.0/24" }, privatelink={ cidr="10.70.10.0/24" } }
nat_gateway = { enabled = true }
vm_size   = "Standard_D2s_v5"
vm_count  = 2
acr_sku   = "Standard"
