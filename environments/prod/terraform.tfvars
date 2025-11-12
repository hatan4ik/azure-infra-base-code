rg_name   = "rg-example-prod"
vnet_cidr = ["10.80.0.0/16"]
subnets = { agents={ cidr="10.80.1.0/24" }, privatelink={ cidr="10.80.10.0/24" } }
nat_gateway = { enabled = true }
vm_size   = "Standard_D4s_v5"
vm_count  = 3
acr_sku   = "Premium"
