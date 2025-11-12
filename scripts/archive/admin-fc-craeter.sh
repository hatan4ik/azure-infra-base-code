#!/usr/bin/env bash
# admin-fc-creator.sh
set -euo pipefail

# --- EDIT OR PRE-EXPORT THESE ---
ADO_ORG_URL="${ADO_ORG_URL:-https://dev.azure.com/ExampleCorpOps}"
ADO_PROJECT="${ADO_PROJECT:-ExampleCorp}"
SC_NAME="${SC_NAME:-Azure-Admin-For-FC}"
SP_NAME="${SP_NAME:-sp-ado-admin-fc}"

echo ">> Using DevOps org: $ADO_ORG_URL | project: $ADO_PROJECT"

# Ensure extension & defaults
az extension show --name azure-devops >/dev/null 2>&1 || az extension add --name azure-devops
az devops configure --defaults organization="$ADO_ORG_URL" project="$ADO_PROJECT"

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
SUBSCRIPTION_NAME="$(az account show --query name -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"

echo ">> Creating (or reusing) Service Principal '$SP_NAME' with temporary Owner on /subscriptions/$SUBSCRIPTION_ID"
SP_JSON="$(az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role Owner \
  --scopes "/subscriptions/$SUBSCRIPTION_ID" \
  --years 1 -o json)"

APP_ID="$(jq -r .appId <<<"$SP_JSON")"
APP_SECRET="$(jq -r .password <<<"$SP_JSON")"

# >>> IMPORTANT: pass the key via env var (no CLI flag)
export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY="$APP_SECRET"

echo ">> Creating Azure RM service connection '$SC_NAME' (SP manual)"
SC_ID="$(az devops service-endpoint azurerm create \
  --name "$SC_NAME" \
  --azure-rm-service-principal-id "$APP_ID" \
  --azure-rm-tenant-id "$TENANT_ID" \
  --azure-rm-subscription-id "$SUBSCRIPTION_ID" \
  --azure-rm-subscription-name "$SUBSCRIPTION_NAME" \
  --query id -o tsv)"

echo ">> Authorizing '$SC_NAME' for all pipelines"
az devops service-endpoint update \
  --id "$SC_ID" \
  --enable-for-all true >/dev/null

echo "== Created =="
az devops service-endpoint show --id "$SC_ID" \
  --query "{id:id,name:name,type:type,scheme:authorization.scheme}" -o table
