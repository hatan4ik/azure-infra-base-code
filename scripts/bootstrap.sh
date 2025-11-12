#!/usr/bin/env bash
set -euo pipefail

# ========= Input validation =========
validate_required_vars() {
  local missing=()
  for var in STATE_RG STATE_SA STATE_CONTAINER KV_NAME LAW_NAME ACR_NAME LOCATION; do
    [[ -n "${!var:-}" ]] || missing+=("$var")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required variables: ${missing[*]}" >&2
    exit 1
  fi
}

# ========= Ensure dependencies =========
ensure_dependencies() {
  command -v jq >/dev/null 2>&1 || { sudo apt-get update -y && sudo apt-get install -y jq; }
  command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI not found" >&2; exit 1; }
}

validate_required_vars
ensure_dependencies

echo ">> Using subscription:"
az account show --query "{id:id,name:name,tenantId:tenantId}" -o tsv | awk '{printf "   - %s (tenant %s)\n",$2,$3}'

subId="$(az account show --query id -o tsv)"
rgId="/subscriptions/${subId}/resourceGroups/${STATE_RG}"

declare -a AZ_TAG_ARGS=(
  "BusinessUnit=${TAG_BusinessUnit:-core}"
  "Environment=${TAG_Environment:-prod}"
  "Owner=${TAG_Owner:-platform-team}"
  "CostCenter=${TAG_CostCenter:-cc-001}"
  "System=${TAG_System:-example-platform}"
  "Project=${TAG_Project:-example}"
  "Lifecycle=${TAG_Lifecycle:-long-lived}"
  "Contact=${TAG_Contact:-devops@example.com}"
)

tag_merge(){ az resource tag --ids "$1" --is-incremental --tags "${AZ_TAG_ARGS[@]}" >/dev/null; }

# RG
if az group show -n "${STATE_RG}" >/dev/null 2>&1; then
  tag_merge "$rgId"
else
  az group create -n "${STATE_RG}" -l "${LOCATION}" --tags "${AZ_TAG_ARGS[@]}" -o none
fi

# tfstate SA
if az storage account show -g "${STATE_RG}" -n "${STATE_SA}" >/dev/null 2>&1; then
  SA_ID="$(az storage account show -g "${STATE_RG}" -n "${STATE_SA}" --query id -o tsv)"
  tag_merge "$SA_ID"
else
  az storage account create -g "${STATE_RG}" -n "${STATE_SA}" -l "${LOCATION}"         --sku Standard_LRS --kind StorageV2         --min-tls-version TLS1_2 --allow-blob-public-access false --https-only true         --tags "${AZ_TAG_ARGS[@]}" -o none
fi

az storage container create --name "${STATE_CONTAINER}" --account-name "${STATE_SA}" --auth-mode login --public-access off -o none || true
SA_ID="$(az storage account show -g "${STATE_RG}" -n "${STATE_SA}" --query id -o tsv)"

# KeyVault hardened
if ! az keyvault show -n "${KV_NAME}" -g "${STATE_RG}" >/dev/null 2>&1; then
  az keyvault create -n "${KV_NAME}" -g "${STATE_RG}" -l "${LOCATION}"         --enable-rbac-authorization true         --retention-days "${KV_RETENTION_DAYS}"         --public-network-access "${KV_PUBLIC_NETWORK_ACCESS}"         --tags "${AZ_TAG_ARGS[@]}" -o none
  az keyvault update -n "${KV_NAME}" -g "${STATE_RG}" --enable-purge-protection true -o none
else
  KV_JSON="$(az keyvault show -n "${KV_NAME}" -g "${STATE_RG}")"
  KV_ID="$(echo "$KV_JSON" | jq -r '.id')"
  tag_merge "$KV_ID"
  az keyvault update -n "${KV_NAME}" -g "${STATE_RG}" --enable-rbac-authorization true -o none
  az keyvault update -n "${KV_NAME}" -g "${STATE_RG}" --public-network-access "${KV_PUBLIC_NETWORK_ACCESS}" -o none || true
  purgeEnabled="$(echo "$KV_JSON" | jq -r '.properties.enablePurgeProtection // false')"
  if [[ "$purgeEnabled" != "true" ]]; then
    az keyvault update -n "${KV_NAME}" -g "${STATE_RG}" --enable-purge-protection true -o none
  fi
fi
KV_ID="$(az keyvault show -n "${KV_NAME}" -g "${STATE_RG}" --query id -o tsv)"

# LAW
if az monitor log-analytics workspace show -g "${STATE_RG}" -n "${LAW_NAME}" >/dev/null 2>&1; then
  LAW_ID="$(az monitor log-analytics workspace show -g "${STATE_RG}" -n "${LAW_NAME}" --query id -o tsv)"
  tag_merge "$LAW_ID"
else
  az monitor log-analytics workspace create -g "${STATE_RG}" -n "${LAW_NAME}" -l "${LOCATION}" --sku "${LAW_SKU}" --tags "${AZ_TAG_ARGS[@]}" -o none
  LAW_ID="$(az monitor log-analytics workspace show -g "${STATE_RG}" -n "${LAW_NAME}" --query id -o tsv)"
fi

enable_diag() {
  local rid="$1" name="$2"
  local cats logs metrics
  cats="$(az monitor diagnostic-settings categories list --resource "$rid" 2>/dev/null || echo '{}')"
  logs="[]"; metrics="[]"
  echo "$cats" | jq -e '.value[] | select(.type=="Log" and .name=="AuditEvent")' >/dev/null 2>&1 && logs='[{"category":"AuditEvent","enabled":true}]'
  echo "$cats" | jq -e '.value[] | select(.type=="Metric" and .name=="AllMetrics")' >/dev/null 2>&1 && metrics='[{"category":"AllMetrics","enabled":true}]'
  if az monitor diagnostic-settings list --resource "$rid" -o tsv --query "value[?name=='$name'].name" | grep -q .; then
    az monitor diagnostic-settings update --name "$name" --resource "$rid" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null
  else
    az monitor diagnostic-settings create --name "$name" --resource "$rid" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null 2>&1 ||         az monitor diagnostic-settings create --name "$name" --resource "$rid" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null
  fi
}

# ACR
want_pna="${ACR_PUBLIC_NETWORK_ENABLED}"
want_sku="${ACR_SKU}"
if az acr show -g "${STATE_RG}" -n "${ACR_NAME}" >/dev/null 2>&1; then
  ACR_ID="$(az acr show -g "${STATE_RG}" -n "${ACR_NAME}" --query id -o tsv)"
  cur_sku="$(az acr show -g "${STATE_RG}" -n "${ACR_NAME}" --query sku.name -o tsv)"
  if [[ "$want_pna" == "false" && "$cur_sku" != "Premium" ]]; then
    az acr update -n "${ACR_NAME}" --sku Premium >/dev/null
  fi
  if [[ "$want_pna" == "false" ]]; then az acr update -n "${ACR_NAME}" --public-network-enabled false >/dev/null
  else az acr update -n "${ACR_NAME}" --public-network-enabled true >/dev/null; fi
  tag_merge "$ACR_ID"
else
  if [[ "$want_pna" == "false" && "$want_sku" != "Premium" ]]; then want_sku="Premium"; fi
  az acr create -g "${STATE_RG}" -n "${ACR_NAME}" -l "${LOCATION}" --sku "$want_sku" --admin-enabled false --public-network-enabled "$want_pna" --tags "${AZ_TAG_ARGS[@]}" -o none
  ACR_ID="$(az acr show -g "${STATE_RG}" -n "${ACR_NAME}" --query id -o tsv)"
fi

# Diag
enable_diag "$KV_ID"  "ds-kv"
enable_diag "$SA_ID"  "ds-sa"
enable_diag "$ACR_ID" "ds-acr"

# MI RBAC
MI_PRINCIPAL_ID="$(az identity show -g "${MI_RESOURCE_GROUP}" -n "${MI_NAME}" --query principalId -o tsv 2>/dev/null || true)"
if [[ -n "$MI_PRINCIPAL_ID" ]]; then
  for p in "$SA_ID:Storage Blob Data Contributor" "$KV_ID:Key Vault Secrets User" "$ACR_ID:AcrPull"; do
    id="${p%%:*}"; role="${p##*:}"
    if ! az role assignment list --assignee-object-id "$MI_PRINCIPAL_ID" --scope "$id" --query "[?roleDefinitionName=='$role']|[0]" -o tsv | grep -q .; then
      az role assignment create --assignee-object-id "$MI_PRINCIPAL_ID" --role "$role" --scope "$id" -o none || echo "   ! RBAC grant failed for $role on $id"
    fi
  done
else
  echo "   ! MI ${MI_RESOURCE_GROUP}/${MI_NAME} not found; skipping RBAC"
fi

echo "✓ Bootstrap complete."
