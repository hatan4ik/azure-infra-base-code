# FinOps Automations for Azure DevOps → Azure Secure Code-Runner

This folder delivers **low-cost operations** automations:
- **Budgets & Alerts** (Terraform)
- **Cost Exports** to Blob for BI/chargeback (Terraform + Pipeline)
- **Log Analytics retention** tuning (Terraform)
- **Off-hours scale down/up** of VMSS agents (Logic Apps + Managed Identity)
- **ACR image cleanup** (Pipeline + ACR task)
- **Optional**: budget dashboards via Power BI (consuming exports)

## Prereqs
- Azure CLI logged in to target subscription
- Terraform 1.9+
- Storage account (for cost exports) exists or create with IaC
- VMSS agents already provisioned (from main infra)

## Quick Start

### 1) Provision FinOps Foundations
```bash
cd finops/terraform
terraform init
terraform apply -var 'subscription_id=<SUB_ID>'   -var 'budget_amount=300'   -var 'budget_contact_emails=["finops@company.com","cloudops@company.com"]'   -var 'cost_export_storage_rg=rg-core'   -var 'cost_export_storage_account=stcostexports'   -var 'cost_export_container=cmexports'   -auto-approve
```

### 2) Deploy Logic Apps (Scale Down & Up)
Import both JSON workflows in **Logic Apps (Consumption)**:
- `vmss-scale-down.json` (20:00 local)
- `vmss-scale-up.json` (08:00 local)

Give each workflow **System-Assigned Managed Identity**, and **RBAC** on the **VMSS**:
- `Virtual Machine Contributor` (or least-privilege “Scale Set Contributor”) on the specific VMSS resource.

### 3) Create Pipelines
- **ACR cleanup**: `pipelines/finops-acr-cleanup.yml`
- **Off-hours scale (fallback)**: `pipelines/finops-offhours-scale.yml`
- **Cost export runner**: `pipelines/finops-cost-export-run.yml`

Set variable `AZ_SUBSCRIPTION` in each pipeline to **My-ARM-Connection-OIDC** (or your OIDC SC).

## Variables & Tags
- Terraform enforces common tags: `env`, `owner`, `costCenter`
- Budgets apply at **subscription level**
- Cost exports write daily CSV/Parquet to blob path: `cmexports/<YYYY-MM-DD>/...`

## Ops Tips
- Keep **Log Analytics retention** at 30 days max; export older to Blob
- Use **Standard** ACR unless you need **Premium** (PE, replication, Defender scanning)
- Share **NAT Gateway** per region; avoid Azure Firewall unless FQDN filtering is required
