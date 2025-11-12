#!/usr/bin/env bash
set -euo pipefail

# ---- Inputs you might want to set (optional) ----
# If you have many subs/tenants, set one of these. If omitted, the current az context is used.
#: "${TARGET_SUBSCRIPTION:=}"   # can be sub ID or sub Name; e.g., TARGET_SUBSCRIPTION="00000000-0000-0000-0000-000000000000" or "Prod-Sub"
#: "${TARGET_TENANT:=}"         # optional tenant ID to force az context

# Azure DevOps context (set once or pass via flags on the command)
: "${ADO_ORG_URL:=https://dev.azure.com/<your-org>}"
: "${ADO_PROJECT:=<your-project>}"

# Managed Identity info
: "${RESOURCE_GROUP:=rg-ado-wif}"
: "${MI_NAME:=ado-wif-mi}"

# ---- Set az context (if provided) ----
if [[ -n "${TARGET_TENANT}" ]]; then
  az account tenant set --tenant "$TARGET_TENANT" >/dev/null
fi
if [[ -n "${TARGET_SUBSCRIPTION}" ]]; then
  az account set --subscription "$TARGET_SUBSCRIPTION" >/dev/null
fi

# ---- Discover current subscription + tenant from az context ----
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
SUBSCRIPTION_NAME="$(az account show --query name -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"

# ---- Get Managed Identity clientId (NOT the resource id) ----
MI_CLIENT_ID="$(az identity show -g "$RESOURCE_GROUP" -n "$MI_NAME" --query clientId -o tsv)"

# ---- (Optional) set default ADO org/project for the CLI ----
#az devops configure --defaults organization="$ADO_ORG_URL" project="$ADO_PROJECT" >/dev/null

# ---- Create the ARM service connection (Workload Identity Federation) ----
az devops service-endpoint create --service-endpoint-configuration <(cat <<JSON
{
  "name": "My-ARM-Connection-OIDC",
  "type": "azurerm",
  "url": "https://management.azure.com/",
  "authorization": {
    "parameters": {
      "tenantid": "$TENANT_ID",
      "serviceprincipalid": "$MI_CLIENT_ID",
      "authenticationType": "WorkloadIdentityFederation"
    },
    "scheme": "WorkloadIdentityFederation"
  },
  "data": {
    "subscriptionId": "$SUBSCRIPTION_ID",
    "subscriptionName": "$SUBSCRIPTION_NAME",
    "environment": "AzureCloud",
    "scopeLevel": "Subscription"
  }
}
JSON
)
