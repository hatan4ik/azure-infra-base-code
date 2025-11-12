# ExampleCorp Azure Infrastructure Platform

**Engineering Board Approved Architecture**  
Version 2.0 | Security First • Complete Automation • Robustness & Resilience

---

## Executive Summary

The ExampleCorp Infrastructure Platform is the single source of truth for provisioning, securing, and operating Azure landing zones. This platform eliminates manual configuration, enforces security-by-default, and provides repeatable infrastructure deployment across all environments.

**Key Capabilities:**
- Passwordless OIDC authentication with Azure Workload Identity Federation
- Idempotent infrastructure provisioning with automatic rollback
- Private network connectivity for analytics workloads (Power BI)
- Comprehensive observability with Log Analytics integration
- Zero-trust security model with least-privilege RBAC

---

## Architecture Overview

### High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Azure DevOps Pipelines                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ Variable     │  │ Orchestrator │  │ Validation   │             │
│  │ Groups Setup │→ │ Pipeline     │→ │ & Sanity     │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
└────────────────────────────┬────────────────────────────────────────┘
                             │ OIDC (Workload Identity)
                             ↓
┌─────────────────────────────────────────────────────────────────────┐
│                        Azure Subscription                           │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Stage 01: Bootstrap                                         │  │
│  │  • Resource Groups    • Key Vault (RBAC + Purge Protection)│  │
│  │  • Storage Account    • Log Analytics Workspace            │  │
│  │  • Container Registry • Diagnostic Settings                │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                             ↓                                       │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Stage 02: Core Network                                      │  │
│  │  • Virtual Network    • Private DNS Zones                   │  │
│  │  • Subnets (Workload, PE, Gateway)                         │  │
│  │  • Private Endpoints  • VNet Links                          │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                             ↓                                       │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Stage 03: Customer Storage                                  │  │
│  │  • ADLS Gen2 Accounts • Containers                          │  │
│  │  • Private Endpoints  • RBAC Assignments                    │  │
│  │  • Diagnostic Settings                                      │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                             ↓                                       │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Stage 04: Power BI Gateway (Optional)                       │  │
│  │  • Delegated Subnet   • VNet Gateway Resource               │  │
│  │  • Environment Links  • Provider Registration               │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Security Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Entra ID (Azure AD)                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ User-Assigned Managed Identity: ado-wif-mi                   │  │
│  │  • Federated Credential (OIDC Trust)                         │  │
│  │  • Subject: sc://ExampleCorpOps/ExampleCorp/My-ARM-Conn-OIDC│  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ Token Exchange (No Secrets)
                             ↓
┌─────────────────────────────────────────────────────────────────────┐
│                    Azure Resource Manager                           │
│                                                                     │
│  RBAC Assignments (Least Privilege):                               │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Subscription Level:                                          │  │
│  │  • Contributor (infrastructure provisioning)                 │  │
│  │                                                              │  │
│  │ Key Vault Level:                                             │  │
│  │  • Key Vault Secrets User (read secrets)                    │  │
│  │                                                              │  │
│  │ Storage Account Level:                                       │  │
│  │  • Storage Blob Data Contributor (state management)         │  │
│  │                                                              │  │
│  │ Container Registry Level:                                    │  │
│  │  • AcrPull (image retrieval)                                 │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Network Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Core Virtual Network                             │
│                    CIDR: 10.100.0.0/16                              │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Workloads Subnet: 10.100.0.0/24                              │  │
│  │  • Application workloads                                     │  │
│  │  • Compute resources                                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Private Endpoints Subnet: 10.100.1.0/24                      │  │
│  │  • PE: Key Vault                                             │  │
│  │  • PE: Storage Accounts (blob, dfs)                          │  │
│  │  • PE: Container Registry                                    │  │
│  │  • PE: Customer ADLS Gen2                                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Power BI Gateway Subnet: 10.100.2.0/27 (Optional)           │  │
│  │  • Delegated to: Microsoft.PowerPlatform/vnetaccesslinks    │  │
│  │  • Microsoft-managed gateway instances                       │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Private DNS Zones:                                                │
│  • privatelink.blob.core.windows.net                               │
│  • privatelink.dfs.core.windows.net                                │
│  • privatelink.vaultcore.azure.net                                 │
│  • privatelink.azurecr.io                                          │
└─────────────────────────────────────────────────────────────────────┘
```

### Power BI Private Connectivity Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Power BI Service (SaaS)                          │
│                    app.powerbi.com                                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ Data Refresh Request
                             ↓
┌─────────────────────────────────────────────────────────────────────┐
│              Microsoft.PowerPlatform VNet Gateway                   │
│              (Managed by Microsoft, runs in your VNet)              │
│                                                                     │
│  Location: Delegated Subnet (10.100.2.0/27)                        │
│  Associated Environments: [Power Platform Env IDs]                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ Private Network Traffic
                             ↓
┌─────────────────────────────────────────────────────────────────────┐
│              Private Endpoint (Storage Account)                     │
│              IP: 10.100.1.x (from PE Subnet)                        │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Customer ADLS Gen2 Storage                                   │  │
│  │  • Public Network Access: Disabled                           │  │
│  │  • Private Endpoint Enabled                                  │  │
│  │  • DNS: privatelink.dfs.core.windows.net                     │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

Result: Power BI → VNet Gateway → Private Endpoint → Storage
        (No public internet exposure)
```

---

## Repository Structure

```
azure-infra-base-code/
├── pipelines/
│   ├── azure-pipelines.yaml              # Main orchestrator
│   ├── 03-var-groups-kve.yaml            # Variable group management
│   ├── 90-nuke-core-net.yaml             # Teardown pipeline
│   ├── script-validation.yaml            # CI quality gates
│   ├── stages/
│   │   ├── 00-variable-groups.stage.yml  # VG seeding stage
│   │   ├── 01-bootstrap.stage.yml        # Bootstrap stage
│   │   ├── 02-vnet-dns-pe.stage.yml      # Network stage
│   │   ├── 03-customer-storage.stage.yml # Storage stage
│   │   ├── 04-powerbi-gateway.stage.yml  # Power BI stage
│   │   └── 90-nuke-core-net.stage.yml    # Teardown stage
│   ├── templates/
│   │   ├── oidc-sanity.yaml              # OIDC validation
│   │   ├── steps-terraform.yml           # Terraform steps
│   │   └── job.customer-storage.yaml     # Storage job template
│   └── steps/
│       └── prepare-scripts.step.yml      # Script preparation
├── scripts/
│   ├── bootstrap.sh                      # Bootstrap implementation
│   ├── core_network.sh                   # Network implementation
│   ├── vnet_dns_pe.sh                    # VNet/DNS/PE provisioning
│   ├── customer_storage.sh               # Storage provisioning
│   ├── powerbi_gateway.sh                # Power BI gateway setup
│   ├── create-oidc-connection-from-mi.sh # OIDC setup
│   ├── cleanup-oidc-mi-connection.sh     # OIDC cleanup
│   ├── list-powerbi-environments.sh      # Power BI helper
│   ├── check-powerbi-gateway.sh          # Gateway validation
│   └── README.md                         # Script documentation
├── environments/
│   ├── dev/
│   │   ├── main.tf                       # Terraform entry point
│   │   ├── variables.tf                  # Variable definitions
│   │   └── backend.hcl                   # State backend config
│   ├── stage/
│   └── prod/
├── WIKI/
│   ├── 00_Overview.md                    # Platform overview
│   ├── 01_Architecture.md                # Architecture details
│   ├── 02_Getting_Started.md             # Onboarding guide
│   ├── 05_Security.md                    # Security policies
│   ├── 06_FinOps.md                      # Cost management
│   └── 07_Troubleshooting.md             # Runbooks
├── README.md                             # This file
├── Platform_Documentation.md             # Component reference
├── SCRIPT_CLEANUP.md                     # Cleanup tracking
└── review.md                             # Board assessment
```

---

## Getting Started

### Prerequisites

**Required Tools:**
- Azure CLI ≥ 2.50.0
- jq ≥ 1.6
- Python 3.8+
- Git
- Azure DevOps CLI extension

**Required Permissions:**
- Azure Subscription: Contributor + User Access Administrator
- Azure DevOps: Project Administrator
- Entra ID: Application Administrator (for MI creation)

### Step 1: Create Managed Identity & Federated Credential

```bash
# Set variables
SUBSCRIPTION_ID="<your-subscription-id>"
TENANT_ID="<your-tenant-id>"
ADO_ORG="ExampleCorpOps"
ADO_PROJECT="ExampleCorp"
SC_NAME="My-ARM-Connection-OIDC"

# Create resource group
az group create -n rg-ado-wif -l eastus

# Create user-assigned managed identity
az identity create -g rg-ado-wif -n ado-wif-mi

# Get identity details
MI_CLIENT_ID=$(az identity show -g rg-ado-wif -n ado-wif-mi --query clientId -o tsv)
MI_PRINCIPAL_ID=$(az identity show -g rg-ado-wif -n ado-wif-mi --query principalId -o tsv)

# Assign subscription-level roles
az role assignment create \
  --assignee-object-id $MI_PRINCIPAL_ID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID

az role assignment create \
  --assignee-object-id $MI_PRINCIPAL_ID \
  --role "User Access Administrator" \
  --scope /subscriptions/$SUBSCRIPTION_ID

# Create federated credential
az identity federated-credential create \
  -g rg-ado-wif \
  --identity-name ado-wif-mi \
  --name ado-federated-credential \
  --issuer "https://vstoken.dev.azure.com/<your-org-id>" \
  --subject "sc://${ADO_ORG}/${ADO_PROJECT}/${SC_NAME}" \
  --audiences "api://AzureADTokenExchange"
```

### Step 2: Create OIDC Service Connection

```bash
# Run the automated script
cd scripts/
export RESOURCE_GROUP="rg-ado-wif"
export MI_NAME="ado-wif-mi"
export SC_NAME="My-ARM-Connection-OIDC"
export ADO_ORG_URL="https://dev.azure.com/ExampleCorpOps"
export ADO_PROJECT="ExampleCorp"

./create-oidc-connection-from-mi.sh
```

### Step 3: Configure Variable Groups

```bash
# Run variable group setup pipeline
az pipelines run \
  --name "03-var-groups-kve" \
  --organization "https://dev.azure.com/ExampleCorpOps" \
  --project "ExampleCorp"
```

This creates:
- `vg-core-bootstrap` - Bootstrap configuration
- `vg-core-network` - Network configuration
- `vg-customer-<slug>` - Customer-specific settings
- `vg-powerbi-gateway` - Power BI gateway settings (optional)

### Step 4: Deploy Infrastructure

```bash
# Run main orchestrator pipeline
az pipelines run \
  --name "azure-pipelines" \
  --organization "https://dev.azure.com/ExampleCorpOps" \
  --project "ExampleCorp" \
  --variables RUN_VARS_SETUP=false
```

### Step 5: Validate Deployment

```bash
# Run OIDC sanity check
az pipelines run \
  --name "sanity-check" \
  --organization "https://dev.azure.com/ExampleCorpOps" \
  --project "ExampleCorp"
```

---

## Configuration Reference

### Bootstrap Variables (vg-core-bootstrap)

| Variable | Description | Example |
|----------|-------------|---------|
| `STATE_RG` | Resource group for state | `rg-example-tfstate` |
| `STATE_SA` | Storage account for Terraform state | `stexampletfstate` |
| `STATE_CONTAINER` | Blob container name | `tfstate` |
| `KV_NAME` | Key Vault name | `kv-example-platform` |
| `KV_RETENTION_DAYS` | Soft-delete retention | `30` |
| `KV_PUBLIC_NETWORK_ACCESS` | Public access | `Disabled` |
| `LAW_NAME` | Log Analytics workspace | `law-example-platform` |
| `ACR_NAME` | Container registry | `acrexampleplatform` |
| `ACR_SKU` | Registry SKU | `Premium` |
| `ACR_PUBLIC_NETWORK_ENABLED` | Public access | `false` |
| `MI_RESOURCE_GROUP` | MI resource group | `rg-ado-wif` |
| `MI_NAME` | Managed identity name | `ado-wif-mi` |
| `LOCATION` | Azure region | `eastus` |

### Network Variables (vg-core-network)

| Variable | Description | Example |
|----------|-------------|---------|
| `NET_RG` | Network resource group | `rg-example-network` |
| `VNET_NAME` | Virtual network name | `vnet-example-core` |
| `VNET_CIDR` | VNet address space | `10.100.0.0/16` |
| `SNET_WORKLOADS_NAME` | Workloads subnet | `snet-workloads` |
| `SNET_WORKLOADS_CIDR` | Workloads CIDR | `10.100.0.0/24` |
| `SNET_PE_NAME` | Private endpoints subnet | `snet-private-endpoints` |
| `SNET_PE_CIDR` | PE subnet CIDR | `10.100.1.0/24` |
| `Z_BLOB` | Blob DNS zone | `privatelink.blob.core.windows.net` |
| `Z_DFS` | DFS DNS zone | `privatelink.dfs.core.windows.net` |
| `Z_KV` | Key Vault DNS zone | `privatelink.vaultcore.azure.net` |
| `Z_ACR` | ACR DNS zone | `privatelink.azurecr.io` |
| `ENABLE_PE_KV` | Enable KV private endpoint | `true` |
| `ENABLE_PE_ACR` | Enable ACR private endpoint | `true` |

### Power BI Gateway Variables (vg-powerbi-gateway)

| Variable | Description | Example |
|----------|-------------|---------|
| `ENABLE_PBI_GATEWAY` | Enable Power BI gateway | `true` |
| `PBI_RG` | Gateway resource group | `rg-example-powerbi` |
| `PBI_LOCATION` | Gateway location | `eastus` |
| `PBI_GATEWAY_NAME` | Gateway resource name | `pbi-vnet-gateway` |
| `PBI_VNET_RG` | VNet resource group | `rg-example-network` |
| `PBI_VNET_NAME` | VNet name | `vnet-example-core` |
| `PBI_SUBNET_NAME` | Delegated subnet | `snet-powerbi-gateway` |
| `PBI_SUBNET_CIDR` | Subnet CIDR | `10.100.2.0/27` |
| `PBI_DELEGATION` | Delegation service | `Microsoft.PowerPlatform/vnetaccesslinks` |
| `PBI_ENVIRONMENT_IDS` | Environment IDs (comma-separated) | `/providers/Microsoft.PowerPlatform/...` |
| `PBI_ENVIRONMENT_LINKS` | Admin portal URLs (comma-separated) | `https://admin.powerplatform.microsoft.com/...` |
| `PBI_GATEWAY_API_VERSION` | API version | `2020-10-30-preview` |

---

## Operations Guide

### Daily Operations

**Monitor Pipeline Runs:**
```bash
az pipelines runs list \
  --organization "https://dev.azure.com/ExampleCorpOps" \
  --project "ExampleCorp" \
  --top 10
```

**Check Resource Health:**
```bash
# Bootstrap resources
az group show -n rg-example-tfstate
az keyvault show -n kv-example-platform -g rg-example-tfstate
az acr show -n acrexampleplatform -g rg-example-tfstate

# Network resources
az network vnet show -g rg-example-network -n vnet-example-core
az network private-endpoint list -g rg-example-network
```

**Validate OIDC Connection:**
```bash
az pipelines run --name "sanity-check"
```

### Troubleshooting

**OIDC Authentication Failures:**
1. Verify federated credential subject matches service connection
2. Check MI has required RBAC roles
3. Run `pipelines/templates/oidc-sanity.yaml` for detailed diagnostics

**Network Provisioning Issues:**
1. Verify CIDR ranges don't overlap
2. Check subnet delegation for Power BI gateway
3. Validate DNS zone links to VNet

**Power BI Gateway Issues:**
1. Confirm `Microsoft.PowerPlatform` provider is registered
2. Verify subnet delegation: `Microsoft.PowerPlatform/vnetaccesslinks`
3. Check gateway provisioning state: `scripts/check-powerbi-gateway.sh`
4. Validate environment IDs format

**Script Validation Failures:**
```bash
# Run shellcheck locally
find scripts/ -name "*.sh" -not -path "*/archive/*" -exec shellcheck {} \;

# Validate syntax
bash -n scripts/bootstrap.sh
```

### Maintenance Tasks

**Update Variable Groups:**
```bash
az pipelines run --name "03-var-groups-kve"
```

**Rotate Credentials:**
- No credentials to rotate (OIDC-based)
- Review MI RBAC assignments quarterly

**Cost Optimization:**
```bash
# Review resource costs
az consumption usage list \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --query "[?contains(instanceName, 'example')]"
```

**Teardown Non-Production:**
```bash
# Dry run first
az pipelines run \
  --name "90-nuke-core-net" \
  --variables DRY_RUN=true CONFIRM_NUKE=YES

# Execute teardown
az pipelines run \
  --name "90-nuke-core-net" \
  --variables DRY_RUN=false CONFIRM_NUKE=YES
```

---

## Security Best Practices

### Authentication & Authorization
- ✅ Use OIDC (Workload Identity Federation) exclusively
- ✅ Never store service principal secrets in variable groups
- ✅ Apply least-privilege RBAC to managed identity
- ✅ Review role assignments quarterly

### Network Security
- ✅ Disable public network access on all PaaS services
- ✅ Use private endpoints for all storage and Key Vault access
- ✅ Implement network segmentation with subnets
- ✅ Enable diagnostic logging on all network resources

### Data Protection
- ✅ Enable Key Vault purge protection
- ✅ Set soft-delete retention to minimum 30 days
- ✅ Enable storage account soft-delete
- ✅ Enforce TLS 1.2 minimum on all services

### Observability
- ✅ Stream diagnostics to Log Analytics
- ✅ Enable AuditEvent logging on Key Vault
- ✅ Monitor RBAC changes with Activity Log alerts
- ✅ Track pipeline execution metrics

---

## Engineering Guardrails

### Script Standards
- All scripts must include `set -euo pipefail`
- Input validation required for all parameters
- Idempotent operations with existence checks
- Clear error messages with exit codes

### Pipeline Standards
- OIDC service connections only
- Stage templates for orchestration
- Bash scripts for implementation
- Validation gates before deployment

### Code Quality
- shellcheck validation on all scripts
- Syntax validation in CI pipeline
- Required variable checks
- No inline secrets or credentials

---

## Support & Documentation

### Primary Documentation
- `README.md` - This file (architecture & operations)
- `Platform_Documentation.md` - Component reference
- `scripts/README.md` - OIDC setup guide
- `WIKI/` - Detailed guides and runbooks

### Engineering Board Contacts
- Azure Architecture: architecture@example.com
- DevOps: devops@example.com
- Security: security@example.com
- Automation: automation@example.com

### Change Management
- All changes require Engineering Board review
- Follow three pillars: Security, Automation, Resilience
- Document architectural decisions in `review.md`
- Track improvements in GitHub Issues

---

## Appendix

### Glossary
- **OIDC**: OpenID Connect (Workload Identity Federation)
- **UAMI**: User-Assigned Managed Identity
- **PE**: Private Endpoint
- **ADLS**: Azure Data Lake Storage
- **ACR**: Azure Container Registry
- **LAW**: Log Analytics Workspace

### API Versions
- Power BI Gateway: `2020-10-30-preview` (default)
- Azure Resource Manager: `2021-04-01`
- Storage Account: `2021-09-01`

### Compliance
- SOC 2 Type II: Audit logging enabled
- GDPR: Data residency enforced
- HIPAA: Encryption at rest and in transit

---

**Last Updated:** 2024-01-15  
**Engineering Board Approval:** ✅ Approved  
**Next Review:** 2024-04-15