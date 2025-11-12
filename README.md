# ExampleCorp Azure Infrastructure Platform

**Engineering Board Approved Architecture**  
Version 2.0 | Security First • Complete Automation • Robustness & Resilience

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture](#architecture)
   - [System Architecture](#system-architecture)
   - [Security Architecture](#security-architecture)
   - [Network Architecture](#network-architecture)
   - [Power BI Connectivity](#power-bi-connectivity)
3. [Repository Structure](#repository-structure)
4. [Zero-to-Hero Deployment](#zero-to-hero-deployment)
   - [Prerequisites](#prerequisites)
   - [Automated Deployment](#automated-deployment)
   - [Verification](#verification)
5. [Configuration Reference](#configuration-reference)
   - [Bootstrap Variables](#bootstrap-variables)
   - [Network Variables](#network-variables)
   - [Customer Storage Variables](#customer-storage-variables)
   - [Power BI Gateway Variables](#power-bi-gateway-variables)
6. [Operations Guide](#operations-guide)
   - [Daily Operations](#daily-operations)
   - [Monitoring](#monitoring)
   - [Maintenance](#maintenance)
7. [Troubleshooting](#troubleshooting)
   - [OIDC Issues](#oidc-issues)
   - [Network Issues](#network-issues)
   - [Power BI Gateway Issues](#power-bi-gateway-issues)
   - [Script Issues](#script-issues)
8. [Security & Compliance](#security--compliance)
9. [Engineering Standards](#engineering-standards)
10. [Appendix](#appendix)

---

## Executive Summary

The ExampleCorp Infrastructure Platform is the single source of truth for provisioning, securing, and operating Azure landing zones. This platform eliminates manual configuration, enforces security-by-default, and provides repeatable infrastructure deployment across all environments.

**Key Capabilities:**
- Passwordless OIDC authentication with Azure Workload Identity Federation
- Idempotent infrastructure provisioning with automatic rollback
- Private network connectivity for analytics workloads (Power BI)
- Comprehensive observability with Log Analytics integration
- Zero-trust security model with least-privilege RBAC
- **100% automated deployment from zero to production in ~25 minutes**

**Engineering Pillars:**
- **Security First** – Passwordless automation via OIDC, least-privilege RBAC, auditable declarations
- **Complete Automation** – No manual steps from bootstrap to teardown; everything is pipelined or scripted
- **Robustness & Resilience** – Idempotent scripts, defensive retries, observability, and safe rollback paths

---

## Architecture

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Azure DevOps Pipelines                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ Zero-to-Hero │  │ Orchestrator │  │ Validation   │             │
│  │ Bootstrap    │→ │ Pipeline     │→ │ & Sanity     │             │
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
│                    CIDR: 10.10.0.0/16                               │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Workloads Subnet: 10.10.0.0/24                               │  │
│  │  • Application workloads                                     │  │
│  │  • Compute resources                                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Private Endpoints Subnet: 10.10.1.0/24                       │  │
│  │  • PE: Key Vault                                             │  │
│  │  • PE: Storage Accounts (blob, dfs)                          │  │
│  │  • PE: Container Registry                                    │  │
│  │  • PE: Customer ADLS Gen2                                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Power BI Gateway Subnet: 10.10.3.0/27 (Optional)            │  │
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

### Power BI Connectivity

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
│  Location: Delegated Subnet (10.10.3.0/27)                         │
│  Associated Environments: [Power Platform Env IDs]                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ Private Network Traffic
                             ↓
┌─────────────────────────────────────────────────────────────────────┐
│              Private Endpoint (Storage Account)                     │
│              IP: 10.10.1.x (from PE Subnet)                         │
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
├── terraform/                            # Terraform implementation (alternative)
│   ├── modules/
│   │   ├── managed-identity/             # OIDC MI module
│   │   ├── bootstrap/                    # Core infrastructure module
│   │   ├── network/                      # Network module
│   │   ├── storage/                      # Storage module
│   │   └── powerbi-gateway/              # Power BI gateway module
│   ├── environments/
│   │   ├── dev/
│   │   ├── stage/
│   │   └── prod/
│   └── README.md                         # Terraform documentation
├── pipelines/
│   ├── 00-zero-to-hero.yaml              # Zero-to-hero bootstrap
│   ├── azure-pipelines.yaml              # Main orchestrator
│   ├── 03-var-groups-kve.yaml            # Variable group management
│   ├── 90-nuke-core-net.yaml             # Teardown pipeline
│   ├── script-validation.yaml            # CI quality gates
│   ├── stages/
│   │   ├── 00-var-groups.stage.yml       # VG seeding stage
│   │   ├── 01-bootstrap.stage.yml        # Bootstrap stage
│   │   ├── 02-vnet-dns-pe.stage.yml      # Network stage
│   │   ├── 03-customer-storage.stage.yml # Storage stage
│   │   └── 04-powerbi-gateway.stage.yml  # Power BI stage
│   ├── templates/
│   │   ├── oidc-sanity.yaml              # OIDC validation
│   │   └── steps-terraform.yml           # Terraform steps
│   └── steps/
│       └── prepare-scripts.step.yml      # Script preparation
├── scripts/
│   ├── bootstrap.sh                      # Bootstrap implementation
│   ├── core_network.sh                   # Network implementation
│   ├── vnet_dns_pe.sh                    # VNet/DNS/PE provisioning
│   ├── customer_storage.sh               # Storage provisioning
│   ├── powerbi_gateway.sh                # Power BI gateway setup
│   ├── create-oidc-connection-from-mi.sh # OIDC setup
│   └── cleanup-oidc-mi-connection.sh     # OIDC cleanup
├── environments/
│   ├── dev/
│   ├── stage/
│   └── prod/
├── WIKI/                                 # Legacy documentation (archived)
├── cloud-init/
│   └── agents.yaml                       # VMSS agent bootstrap
├── README.md                             # This file
└── review.md                             # Board assessment
```

---

## Zero-to-Hero Deployment

### Prerequisites

**Required:**
- Azure subscription with Owner or Contributor + User Access Administrator
- Azure DevOps organization and project
- Azure CLI installed locally

**One-Time ADO Configuration:**
```bash
# Enable System.AccessToken in Azure DevOps
# Project Settings → Pipelines → Settings
# Disable: "Limit job authorization scope to current project"
```

### Automated Deployment

**Step 1: Run Zero-to-Hero Pipeline**

```bash
# Import and run the bootstrap pipeline
az pipelines run \
  --name "00-zero-to-hero" \
  --organization "https://dev.azure.com/YourOrg" \
  --project "YourProject" \
  --parameters \
    SUBSCRIPTION_ID="<your-subscription-id>" \
    TENANT_ID="<your-tenant-id>" \
    ADO_ORG="YourOrg" \
    ADO_PROJECT="YourProject" \
    AZURE_LOCATION="eastus"
```

**What This Creates:**
- ✅ Managed Identity with RBAC roles
- ✅ Federated Credential for OIDC
- ✅ Service Connection (passwordless)
- ✅ ADO Environments
- ✅ Variable Groups with configuration

**Duration:** ~5-10 minutes

**Step 2: Deploy Infrastructure**

```bash
# Run the main infrastructure pipeline
az pipelines run \
  --name "azure-pipelines" \
  --organization "https://dev.azure.com/YourOrg" \
  --project "YourProject"
```

**What This Deploys:**
- ✅ Bootstrap (RG, Storage, Key Vault, ACR, Log Analytics)
- ✅ Core Network (VNet, Subnets, DNS Zones, Private Endpoints)
- ✅ Customer Storage (ADLS Gen2 with Private Endpoints)
- ✅ Power BI Gateway (Optional)

**Duration:** ~15-20 minutes

**Total Time:** ~25 minutes from zero to production

### Alternative: Terraform Deployment

For teams preferring Infrastructure as Code with state management:

```bash
# Navigate to Terraform environment
cd terraform/environments/dev

# Initialize with backend
terraform init \
  -backend-config="resource_group_name=rg-tfstate-backend" \
  -backend-config="storage_account_name=sttfstatebackend" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=dev.tfstate"

# Plan and apply
terraform plan -out=tfplan
terraform apply tfplan
```

**See [terraform/README.md](terraform/README.md) for complete Terraform documentation.**

### Configuration Validation

**Before deploying, validate your configuration:**

```bash
# Check for placeholder values
./scripts/validate-config.sh

# Replace placeholders interactively
./scripts/replace-placeholders.sh
```

**What gets validated:**
- Organization and project names
- Subscription and tenant IDs
- Resource naming conventions
- Power BI environment IDs
- Dummy/example values

### Verification

```bash
# Verify Managed Identity
az identity show -g rg-ado-wif -n ado-wif-mi

# Verify Service Connection
az devops service-endpoint list \
  --organization "https://dev.azure.com/YourOrg" \
  --project "YourProject" \
  --query "[?name=='My-ARM-Connection-OIDC']"

# Verify Infrastructure
az group list --query "[?starts_with(name, 'rg-example')]" -o table
az network vnet list -g rg-example-core-net -o table
az keyvault list -g rg-example-tfstate -o table

# Run sanity check
az pipelines run --name "sanity-check"
```

---

## Configuration Reference

### Bootstrap Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STATE_RG` | Resource group for state | `rg-example-tfstate` |
| `STATE_SA` | Storage account for Terraform state | `stexampletfstate` |
| `STATE_CONTAINER` | Blob container name | `tfstate` |
| `KV_NAME` | Key Vault name | `kv-example-platform` |
| `KV_RETENTION_DAYS` | Soft-delete retention | `30` |
| `KV_PUBLIC_NETWORK_ACCESS` | Public access | `Disabled` |
| `LAW_NAME` | Log Analytics workspace | `law-example-platform` |
| `LAW_SKU` | Log Analytics SKU | `PerGB2018` |
| `ACR_NAME` | Container registry | `acrexampleplatform` |
| `ACR_SKU` | Registry SKU | `Premium` |
| `ACR_PUBLIC_NETWORK_ENABLED` | Public access | `false` |
| `MI_RESOURCE_GROUP` | MI resource group | `rg-ado-wif` |
| `MI_NAME` | Managed identity name | `ado-wif-mi` |
| `LOCATION` | Azure region | `eastus` |

### Network Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NET_RG` | Network resource group | `rg-example-core-net` |
| `VNET_NAME` | Virtual network name | `vnet-example-core` |
| `VNET_CIDR` | VNet address space | `10.10.0.0/16` |
| `SNET_WORKLOADS_NAME` | Workloads subnet | `snet-workloads` |
| `SNET_WORKLOADS_CIDR` | Workloads CIDR | `10.10.0.0/24` |
| `SNET_PE_NAME` | Private endpoints subnet | `snet-private-endpoints` |
| `SNET_PE_CIDR` | PE subnet CIDR | `10.10.1.0/24` |
| `Z_BLOB` | Blob DNS zone | `privatelink.blob.core.windows.net` |
| `Z_DFS` | DFS DNS zone | `privatelink.dfs.core.windows.net` |
| `Z_KV` | Key Vault DNS zone | `privatelink.vaultcore.azure.net` |
| `Z_ACR` | ACR DNS zone | `privatelink.azurecr.io` |
| `ENABLE_PE_KV` | Enable KV private endpoint | `false` |
| `ENABLE_PE_ACR` | Enable ACR private endpoint | `false` |

### Customer Storage Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CUSTOMER_SLUG` | Customer identifier | `washington` |
| `DATA_RG` | Data resource group | `rg-example-data-washington` |
| `SA_NAME` | Storage account name | Auto-generated |
| `CONTAINERS_CSV` | Container names (comma-separated) | `invoices,archive` |
| `ENABLE_STORAGE_PE` | Enable private endpoints | `true` |
| `LAW_RG` | Log Analytics RG | `rg-example-tfstate` |
| `LAW_NAME` | Log Analytics workspace | `law-example-platform` |

### Power BI Gateway Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ENABLE_PBI_GATEWAY` | Enable Power BI gateway | `false` |
| `PBI_RG` | Gateway resource group | `rg-example-analytics` |
| `PBI_LOCATION` | Gateway location | `eastus` |
| `PBI_GATEWAY_NAME` | Gateway resource name | `pbi-vnet-gateway` |
| `PBI_VNET_RG` | VNet resource group | `rg-example-core-net` |
| `PBI_VNET_NAME` | VNet name | `vnet-example-core` |
| `PBI_SUBNET_NAME` | Delegated subnet | `snet-powerbi-gateway` |
| `PBI_SUBNET_CIDR` | Subnet CIDR | `10.10.3.0/27` |
| `PBI_DELEGATION` | Delegation service | `Microsoft.PowerPlatform/vnetaccesslinks` |
| `PBI_ENVIRONMENT_IDS` | Environment IDs (comma-separated) | Required |
| `PBI_GATEWAY_API_VERSION` | API version | `2020-10-30-preview` |

---

## Operations Guide

### Daily Operations

**Monitor Pipeline Runs:**
```bash
az pipelines runs list \
  --organization "https://dev.azure.com/YourOrg" \
  --project "YourProject" \
  --top 10
```

**Check Resource Health:**
```bash
# Bootstrap resources
az group show -n rg-example-tfstate
az keyvault show -n kv-example-platform -g rg-example-tfstate
az acr show -n acrexampleplatform -g rg-example-tfstate

# Network resources
az network vnet show -g rg-example-core-net -n vnet-example-core
az network private-endpoint list -g rg-example-core-net

# Storage resources
az storage account list -g rg-example-data-washington -o table
```

### Monitoring

**View Diagnostic Logs:**
```bash
# Query Log Analytics
az monitor log-analytics query \
  -w <workspace-id> \
  --analytics-query "AzureDiagnostics | where TimeGenerated > ago(1h)"

# Check Key Vault audit events
az monitor log-analytics query \
  -w <workspace-id> \
  --analytics-query "AzureDiagnostics | where ResourceType == 'VAULTS' and Category == 'AuditEvent'"
```

**Monitor RBAC Changes:**
```bash
# Activity log for role assignments
az monitor activity-log list \
  --resource-group rg-example-tfstate \
  --offset 7d \
  --query "[?contains(operationName.value, 'roleAssignments')]"
```

### Maintenance

**Update Variable Groups:**
```bash
az pipelines run --name "03-var-groups-kve"
```

**Rotate Credentials:**
- No credentials to rotate (OIDC-based)
- Review MI RBAC assignments quarterly

**Update Infrastructure:**
```bash
# Re-run main pipeline (idempotent)
az pipelines run --name "azure-pipelines"
```

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

## Troubleshooting

### OIDC Issues

**Problem:** OIDC authentication fails

**Solution:**
```bash
# 1. Verify federated credential subject matches service connection
az identity federated-credential list \
  -g rg-ado-wif \
  --identity-name ado-wif-mi

# 2. Check MI has required RBAC roles
az role assignment list \
  --assignee <mi-principal-id> \
  --scope /subscriptions/<subscription-id>

# 3. Run OIDC sanity check
az pipelines run --name "sanity-check"
```

### Network Issues

**Problem:** CIDR ranges overlap

**Solution:**
```bash
# Scripts auto-calculate non-overlapping ranges
# Check current VNet address space
az network vnet show \
  -g rg-example-core-net \
  -n vnet-example-core \
  --query addressSpace.addressPrefixes
```

**Problem:** Private endpoint creation fails

**Solution:**
```bash
# Verify subnet has private endpoint policies disabled
az network vnet subnet show \
  -g rg-example-core-net \
  --vnet-name vnet-example-core \
  -n snet-private-endpoints \
  --query privateEndpointNetworkPolicies
```

### Power BI Gateway Issues

**Problem:** Gateway provisioning fails

**Solution:**
```bash
# 1. Confirm provider is registered
az provider show \
  --namespace Microsoft.PowerPlatform \
  --query registrationState

# 2. Verify subnet delegation
az network vnet subnet show \
  -g rg-example-core-net \
  --vnet-name vnet-example-core \
  -n snet-powerbi-gateway \
  --query delegations

# 3. Check gateway provisioning state
bash scripts/check-powerbi-gateway.sh

# 4. Validate environment IDs format
# Should be: /providers/Microsoft.PowerPlatform/locations/<geo>/environments/<id>
```

### Script Issues

**Problem:** Script validation fails

**Solution:**
```bash
# Run shellcheck locally
find scripts/ -name "*.sh" -not -path "*/archive/*" -exec shellcheck {} \;

# Validate syntax
bash -n scripts/bootstrap.sh

# Check for required variables
grep -E "^: \"\${.*:?\?.*}\"" scripts/bootstrap.sh
```

---

## Security & Compliance

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

### Compliance Standards
- **SOC 2 Type II:** Audit logging enabled on all resources
- **GDPR:** Data residency enforced via Azure region selection
- **HIPAA:** Encryption at rest and in transit enforced

---

## Engineering Standards

### Script Standards
- All scripts must include `set -euo pipefail`
- Input validation required for all parameters
- Idempotent operations with existence checks
- Clear error messages with exit codes
- No inline secrets or credentials

### Pipeline Standards
- OIDC service connections only
- Stage templates for orchestration
- Bash scripts for implementation
- Validation gates before deployment
- System.AccessToken for REST API calls

### Code Quality
- shellcheck validation on all scripts
- Syntax validation in CI pipeline
- Required variable checks
- Automated testing via script-validation.yaml

### Testing Standards
- Unit tests for all bash scripts (Bats framework)
- Integration tests for Terraform modules
- Configuration validation before deployment
- CI/CD pipeline includes all test suites
- Tests run on every PR and commit

**Run tests locally:**
```bash
# Run all tests
./tests/run-all-tests.sh

# Run unit tests only
bats tests/unit/*.bats

# Run Terraform validation
bash tests/integration/test_terraform.sh

# Validate configuration
bash scripts/validate-config.sh
```

### Naming Conventions
- Resource Groups: `rg-<purpose>-<environment>`
- Storage Accounts: `st<purpose><environment>` (lowercase, no hyphens)
- Key Vaults: `kv-<purpose>-<environment>`
- Virtual Networks: `vnet-<purpose>-<environment>`
- Subnets: `snet-<purpose>`

---

## Appendix

### Deployment Options

| Method | Time | Manual Steps | Use Case |
|--------|------|--------------|----------|
| **Zero-to-Hero (Azure CLI)** | ~25 min | 1 (enable token) | New deployments, automation |
| **Terraform** | ~30 min | 2 (backend + init) | IaC, state management, drift detection |
| **Manual Setup** | ~45 min | 5 steps | Learning, customization |
| **Existing Infrastructure** | ~15 min | 0 | Updates, changes |

### Implementation Comparison

| Feature | Azure CLI (Primary) | Terraform (Alternative) |
|---------|---------------------|-------------------------|
| **Approach** | Bash scripts | HCL modules |
| **State** | Stateless | Stateful (tfstate) |
| **Idempotency** | Manual checks | Built-in |
| **Modularity** | Script functions | Native modules |
| **Drift Detection** | Manual | `terraform plan` |
| **Speed** | Faster | Moderate |
| **Learning Curve** | Low | Moderate |
| **Best For** | Quick deployments, CI/CD | Complex infrastructure, teams familiar with Terraform |

### Pipeline Reference

| Pipeline | Purpose | When to Run |
|----------|---------|-------------|
| `00-zero-to-hero.yaml` | Bootstrap all prerequisites | Once per environment |
| `azure-pipelines.yaml` | Deploy infrastructure | Every deployment |
| `03-var-groups-kve.yaml` | Update variable groups | Configuration changes |
| `script-validation.yaml` | Validate scripts | On PR/commit |
| `90-nuke-core-net.yaml` | Teardown infrastructure | Cleanup only |

### Glossary

- **OIDC**: OpenID Connect (Workload Identity Federation)
- **UAMI**: User-Assigned Managed Identity
- **PE**: Private Endpoint
- **ADLS**: Azure Data Lake Storage
- **ACR**: Azure Container Registry
- **LAW**: Log Analytics Workspace
- **VG**: Variable Group
- **Zero-to-Hero**: Fully automated deployment from nothing to production

### API Versions

- Power BI Gateway: `2020-10-30-preview` (default)
- Azure Resource Manager: `2021-04-01`
- Storage Account: `2021-09-01`
- Azure DevOps REST API: `7.1-preview.2`

### Support Contacts

- **Azure Architecture:** architecture@example.com
- **DevOps:** devops@example.com
- **Security:** security@example.com
- **Automation:** automation@example.com

### Change Management

- All changes require Engineering Board review
- Follow three pillars: Security, Automation, Resilience
- Document architectural decisions
- Track improvements in GitHub Issues

---

**Last Updated:** 2024-01-15  
**Engineering Board Approval:** ✅ Approved - Zero-to-Hero Certified  
**Automation Level:** 100% (after initial ADO configuration)  
**Next Review:** 2024-04-15