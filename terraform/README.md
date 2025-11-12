# Terraform Implementation - Zero-to-Hero

Complete Terraform implementation matching the Azure CLI zero-to-hero architecture.

## Architecture

This Terraform implementation provides the same 4-stage deployment as the Azure CLI version:

1. **Managed Identity** - OIDC setup with federated credentials
2. **Bootstrap** - Core infrastructure (Storage, Key Vault, ACR, Log Analytics)
3. **Network** - VNet, subnets, DNS zones, private endpoints
4. **Storage** - Customer ADLS Gen2 with private endpoints
5. **Power BI Gateway** - Optional VNet gateway for analytics

## Module Structure

```
terraform/
├── modules/
│   ├── managed-identity/    # OIDC managed identity with RBAC
│   ├── bootstrap/            # Core platform resources
│   ├── network/              # VNet, subnets, DNS zones
│   ├── storage/              # ADLS Gen2 with private endpoints
│   └── powerbi-gateway/      # Power BI VNet gateway
└── environments/
    ├── dev/
    ├── stage/
    └── prod/
```

## Prerequisites

- Terraform >= 1.5.0
- Azure CLI authenticated
- Subscription with Contributor + User Access Administrator

## Quick Start

### 1. Initialize Backend

```bash
cd terraform/environments/dev

# Create backend storage (one-time)
az group create -n rg-tfstate-backend -l eastus
az storage account create -n sttfstatebackend -g rg-tfstate-backend -l eastus --sku Standard_LRS
az storage container create -n tfstate --account-name sttfstatebackend
```

### 2. Configure Variables

```bash
# Copy example and edit
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

Required variables:
- `subscription_id` - Your Azure subscription ID
- `tenant_id` - Your Azure tenant ID
- `oidc_issuer` - OIDC issuer URL from Azure DevOps
- `oidc_subject` - OIDC subject (service connection path)

### 3. Deploy

```bash
# Initialize
terraform init \
  -backend-config="resource_group_name=rg-tfstate-backend" \
  -backend-config="storage_account_name=sttfstatebackend" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=dev.tfstate"

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

## Module Details

### Managed Identity Module

Creates user-assigned managed identity with:
- Federated credential for OIDC
- Contributor role at subscription level
- User Access Administrator role

**Usage:**
```hcl
module "managed_identity" {
  source = "../../modules/managed-identity"

  resource_group_name = "rg-ado-wif"
  location            = "eastus"
  identity_name       = "ado-wif-mi"
  subscription_id     = "/subscriptions/xxx"
  oidc_issuer         = "https://vstoken.dev.azure.com/xxx"
  oidc_subject        = "sc://Org/Project/Connection"
}
```

### Bootstrap Module

Creates core platform resources:
- Resource group
- Storage account for Terraform state
- Key Vault (RBAC mode, purge protection)
- Log Analytics workspace
- Container Registry (Premium)
- Diagnostic settings
- RBAC assignments for managed identity

**Usage:**
```hcl
module "bootstrap" {
  source = "../../modules/bootstrap"

  resource_group_name           = "rg-example-tfstate"
  location                      = "eastus"
  storage_account_name          = "stexampletfstate"
  key_vault_name                = "kv-example-platform"
  tenant_id                     = "xxx"
  log_analytics_name            = "law-example-platform"
  acr_name                      = "acrexampleplatform"
  managed_identity_principal_id = module.managed_identity.principal_id
}
```

### Network Module

Creates network infrastructure:
- Virtual network
- Subnets (workloads, private endpoints, Power BI gateway)
- Private DNS zones (blob, dfs, vault, acr)
- VNet links for DNS zones
- Subnet delegation for Power BI

**Usage:**
```hcl
module "network" {
  source = "../../modules/network"

  resource_group_name   = "rg-example-core-net"
  location              = "eastus"
  vnet_name             = "vnet-example-core"
  vnet_cidr             = "10.10.0.0/16"
  subnet_workloads_cidr = "10.10.0.0/24"
  subnet_pe_cidr        = "10.10.1.0/24"
  enable_powerbi_gateway = true
  subnet_pbi_cidr       = "10.10.3.0/27"
}
```

### Storage Module

Creates customer storage:
- Resource group
- ADLS Gen2 storage account
- Containers
- Private endpoints (blob, dfs)
- DNS zone groups
- Diagnostic settings
- RBAC assignments

**Usage:**
```hcl
module "customer_storage" {
  source = "../../modules/storage"

  resource_group_name         = "rg-example-data-washington"
  location                    = "eastus"
  storage_account_name        = "stexamplewashington"
  containers                  = ["invoices", "archive"]
  enable_private_endpoint     = true
  network_resource_group_name = module.network.resource_group_name
  subnet_pe_id                = module.network.subnet_pe_id
  dns_zone_blob_id            = module.network.dns_zone_blob_id
  dns_zone_dfs_id             = module.network.dns_zone_dfs_id
}
```

### Power BI Gateway Module

Creates Power BI VNet gateway:
- Resource group
- Provider registration (Microsoft.PowerPlatform)
- VNet gateway resource
- Environment associations

**Usage:**
```hcl
module "powerbi_gateway" {
  source = "../../modules/powerbi-gateway"

  enable_gateway      = true
  resource_group_name = "rg-example-analytics"
  location            = "eastus"
  gateway_name        = "example-powerbi-gateway"
  vnet_id             = module.network.vnet_id
  subnet_id           = module.network.subnet_pbi_id
  environment_ids     = [
    "/providers/Microsoft.PowerPlatform/locations/unitedstates/environments/Default-xxx"
  ]
}
```

## Comparison: Terraform vs Azure CLI

| Feature | Terraform | Azure CLI (Bash) |
|---------|-----------|------------------|
| **State Management** | Yes (tfstate) | No |
| **Idempotency** | Built-in | Manual checks |
| **Modularity** | Native modules | Script functions |
| **Drift Detection** | `terraform plan` | Manual verification |
| **Dependency Graph** | Automatic | Manual ordering |
| **Rollback** | State-based | Script-based |
| **Learning Curve** | Moderate | Low |
| **Execution Speed** | Slower (API calls) | Faster (direct CLI) |

## Best Practices

### 1. State Management
- Use remote backend (Azure Storage)
- Enable state locking
- Never commit state files to Git

### 2. Secrets Management
- Use Key Vault for secrets
- Never hardcode credentials
- Use managed identities

### 3. Module Versioning
- Pin module versions in production
- Use semantic versioning
- Test in dev before promoting

### 4. Resource Naming
- Follow naming conventions
- Use consistent prefixes
- Include environment in names

### 5. Tagging
- Apply tags consistently
- Include cost center, owner, environment
- Use locals for common tags

## Troubleshooting

### Backend Initialization Fails
```bash
# Verify backend storage exists
az storage account show -n sttfstatebackend -g rg-tfstate-backend

# Check permissions
az role assignment list --assignee <your-user-id> --scope /subscriptions/<sub-id>
```

### Provider Registration Issues
```bash
# Register required providers
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.PowerPlatform
```

### OIDC Authentication Fails
```bash
# Verify federated credential
az identity federated-credential list \
  -g rg-ado-wif \
  --identity-name ado-wif-mi

# Check issuer and subject match
```

### Module Not Found
```bash
# Ensure you're in correct directory
cd terraform/environments/dev

# Re-initialize
terraform init -upgrade
```

## Migration from Azure CLI

To migrate from Azure CLI implementation:

1. **Import existing resources:**
```bash
terraform import module.bootstrap.azurerm_resource_group.tfstate /subscriptions/xxx/resourceGroups/rg-example-tfstate
terraform import module.bootstrap.azurerm_key_vault.main /subscriptions/xxx/resourceGroups/rg-example-tfstate/providers/Microsoft.KeyVault/vaults/kv-example-platform
```

2. **Verify state:**
```bash
terraform plan
# Should show no changes if import successful
```

3. **Gradually adopt:**
- Start with new resources
- Import critical existing resources
- Maintain both during transition

## CI/CD Integration

### Azure DevOps Pipeline

```yaml
trigger:
  branches:
    include: [ main ]

pool:
  vmImage: ubuntu-latest

variables:
  TF_VERSION: 1.5.0

stages:
- stage: Plan
  jobs:
  - job: TerraformPlan
    steps:
    - task: TerraformInstaller@0
      inputs:
        terraformVersion: $(TF_VERSION)
    
    - task: TerraformCLI@0
      inputs:
        command: init
        workingDirectory: terraform/environments/dev
        backendType: azurerm
        backendServiceArm: My-ARM-Connection-OIDC
    
    - task: TerraformCLI@0
      inputs:
        command: plan
        workingDirectory: terraform/environments/dev

- stage: Apply
  dependsOn: Plan
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: TerraformApply
    environment: production
    strategy:
      runOnce:
        deploy:
          steps:
          - task: TerraformCLI@0
            inputs:
              command: apply
              workingDirectory: terraform/environments/dev
```

## Support

For issues or questions:
- Review module documentation in each module's directory
- Check Azure CLI implementation for reference
- Consult Terraform Azure provider docs

---

**Engineering Board Approved**  
**Version:** 1.0  
**Last Updated:** 2024-01-15