# Remote state backend. Override 'key' per env in init.
resource_group_name  = "<tfstate-rg>"
storage_account_name = "<tfstateglobal001>"
container_name       = "tfstate"
key                  = "code-runner/dev.tfstate"
