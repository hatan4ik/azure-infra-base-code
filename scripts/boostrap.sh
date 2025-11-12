#!/usr/bin/env bash
set -euo pipefail

echo ">> Using subscription:"
az account show --query "{id:id,name:name,tenantId:tenantId}" -o tsv | awk '{printf "   - %s (tenant %s)\n",$2,$3}'

subId="$(az account show --query id -o tsv)"
rgId="/subscriptions/${subId}/resourceGroups/$(STATE_RG)"

# ---------- TAGS ----------
declare -a AZ_TAG_ARGS=(
  "BusinessUnit=$(TAG_BusinessUnit:-core)"
  "Environment=$(TAG_Environment:-prod)"
  "Owner=$(TAG_Owner:-platform-team)"
  "CostCenter=$(TAG_CostCenter:-cc-001)"
  "System=$(TAG_System:-example-platform)"
  "Compliance=$(TAG_Compliance:-standard)"
  "LandingZone=$(TAG_LandingZone:-lz-core)"
  "Project=$(TAG_Project:-example)"
  "Lifecycle=$(TAG_Lifecycle:-long-lived)"
  "Contact=$(TAG_Contact:-devops@example.com)"
)

tag_merge() { local rid="$1"; shift; az resource tag --ids "$rid" --is-incremental --tags "$@" --only-show-errors >/dev/null; }

# ---------- RG ----------
echo ">> Ensure Resource Group exists"
if az group show -n "$(STATE_RG)" >/dev/null 2>&1; then
  tag_merge "$rgId" "${AZ_TAG_ARGS[@]}"
else
  az group create -n "$(STATE_RG)" -l "$(LOCATION)" --tags "${AZ_TAG_ARGS[@]}" -o none
fi

# ---------- Storage Account + container ----------
echo ">> Ensure Storage Account (tfstate)"
if az storage account show -g "$(STATE_RG)" -n "$(STATE_SA)" >/dev/null 2>&1; then
  SA_ID="$(az storage account show -g "$(STATE_RG)" -n "$(STATE_SA)" --query id -o tsv)"
  tag_merge "$SA_ID" "${AZ_TAG_ARGS[@]}"
else
  az storage account create \
    -g "$(STATE_RG)" -n "$(STATE_SA)" -l "$(LOCATION)" \
    --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 --allow-blob-public-access false --https-only true \
    --tags "${AZ_TAG_ARGS[@]}" -o none
fi

echo ">> Ensure Blob Container (tfstate)"
az storage container create --name "$(STATE_CONTAINER)" --account-name "$(STATE_SA)" --auth-mode login --public-access off -o none >/dev/null
SA_ID="$(az storage account show -g "$(STATE_RG)" -n "$(STATE_SA)" --query id -o tsv)"

# ---------- Key Vault (hardened) ----------
echo ">> Ensure Key Vault (hardened)"
if ! az keyvault show -n "$(KV_NAME)" -g "$(STATE_RG)" >/dev/null 2>&1; then
  az keyvault create -n "$(KV_NAME)" -g "$(STATE_RG)" -l "$(LOCATION)" \
    --enable-rbac-authorization true \
    --retention-days "$(KV_RETENTION_DAYS)" \
    --public-network-access "$(KV_PUBLIC_NETWORK_ACCESS)" \
    --tags "${AZ_TAG_ARGS[@]}" -o none
  az keyvault update -n "$(KV_NAME)" -g "$(STATE_RG)" --enable-purge-protection true -o none
else
  KV_JSON="$(az keyvault show -n "$(KV_NAME)" -g "$(STATE_RG)")"
  KV_ID="$(echo "$KV_JSON" | jq -r '.id')"
  tag_merge "$KV_ID" "${AZ_TAG_ARGS[@]}"
  az keyvault update -n "$(KV_NAME)" -g "$(STATE_RG)" --enable-rbac-authorization true -o none
  az keyvault update -n "$(KV_NAME)" -g "$(STATE_RG)" --public-network-access "$(KV_PUBLIC_NETWORK_ACCESS)" -o none || true
  purgeEnabled="$(echo "$KV_JSON" | jq -r '.properties.enablePurgeProtection // false')"
  [[ "$purgeEnabled" == "true" ]] || az keyvault update -n "$(KV_NAME)" -g "$(STATE_RG)" --enable-purge-protection true -o none
  haveRet="$(echo "$KV_JSON" | jq -r '.properties.softDeleteRetentionInDays // empty')"
  if [[ -n "$haveRet" && "$haveRet" != "$(KV_RETENTION_DAYS)" ]]; then
    echo "   ! KV retention is ${haveRet} days (immutable). Skipping change to $(KV_RETENTION_DAYS)."
  fi
fi
KV_ID="$(az keyvault show -n "$(KV_NAME)" -g "$(STATE_RG)" --query id -o tsv)"

# ---------- LAW + diagnostics for SA/KV ----------
if [[ -n "${LAW_NAME:-}" && -n "${LAW_RG:-}" ]]; then
  LAW_ID="$(az monitor log-analytics workspace show -g "$LAW_RG" -n "$LAW_NAME" --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$LAW_ID" ]]; then
    enable_diag() {
      local rid="$1" name="$2"
      local cats logs="[]" metrics="[]"
      cats="$(az monitor diagnostic-settings categories list --resource "$rid" 2>/dev/null || echo '{}')"
      echo "$cats" | jq -e '.value[] | select(.type=="Log" and .name=="AuditEvent")' >/dev/null 2>&1 && logs='[{"category":"AuditEvent","enabled":true}]'
      echo "$cats" | jq -e '.value[] | select(.type=="Metric" and .name=="AllMetrics")' >/dev/null 2>&1 && metrics='[{"category":"AllMetrics","enabled":true}]'
      if az monitor diagnostic-settings list --resource "$rid" -o tsv --query "value[?name=='$name'].name" | grep -q .; then
        az monitor diagnostic-settings update --name "$name" --resource "$rid" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null
      else
        az monitor diagnostic-settings create --name "$name" --resource "$rid" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null 2>&1 || \
        az monitor diagnostic-settings create --name "$name" --resource "$rid" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null
      fi
    }
    enable_diag "$SA_ID" "ds-sa"
    enable_diag "$KV_ID" "ds-kv"
  fi
fi

# ---------- ACR (SKU safety + PNA) ----------
echo ">> Ensure ACR"
if az acr show -g "$(STATE_RG)" -n "$(ACR_NAME)" >/dev/null 2>&1; then
  ACR_ID="$(az acr show -g "$(STATE_RG)" -n "$(ACR_NAME)" --query id -o tsv)"
  curSku="$(az acr show -g "$(STATE_RG)" -n "$(ACR_NAME)" --query sku.name -o tsv)"
  if [[ "$(ACR_PUBLIC_NETWORK_ENABLED)" == "false" && "$curSku" != "Premium" ]]; then
    az acr update -n "$(ACR_NAME)" --sku Premium --only-show-errors >/dev/null
  fi
  az acr update -n "$(ACR_NAME)" --public-network-enabled "$(ACR_PUBLIC_NETWORK_ENABLED)" --only-show-errors >/dev/null
  tag_merge "$ACR_ID" "${AZ_TAG_ARGS[@]}"
else
  wantSku="$(ACR_SKU)"
  if [[ "$(ACR_PUBLIC_NETWORK_ENABLED)" == "false" && "$wantSku" != "Premium" ]]; then wantSku="Premium"; fi
  az acr create -g "$(STATE_RG)" -n "$(ACR_NAME)" -l "$(LOCATION)" \
    --sku "$wantSku" --admin-enabled false \
    --public-network-enabled "$(ACR_PUBLIC_NETWORK_ENABLED)" \
    --tags "${AZ_TAG_ARGS[@]}" -o none
  ACR_ID="$(az acr show -g "$(STATE_RG)" -n "$(ACR_NAME)" --query id -o tsv)"
fi

# ---------- MI RBAC (best-effort) ----------
echo ">> Ensure MI RBAC (AcrPull, Blob Data Contributor, KV Secrets User)"
MI_PRINCIPAL_ID="$(az identity show -g "$(MI_RESOURCE_GROUP)" -n "$(MI_NAME)" --query principalId -o tsv 2>/dev/null || true)"
assign_role() {
  local scope="$1" role="$2"
  [[ -z "$MI_PRINCIPAL_ID" ]] && return 0
  az role assignment list --assignee-object-id "$MI_PRINCIPAL_ID" --scope "$scope" \
    --query "[?roleDefinitionName=='$role']|[0]" -o tsv | grep -q . || \
  az role assignment create --assignee-object-id "$MI_PRINCIPAL_ID" --role "$role" --scope "$scope" -o none 2>/dev/null || \
  echo "   ! Could not assign $role on $scope (need UA/Owner)."
}
[[ -n "${ACR_ID:-}" ]] && assign_role "$ACR_ID" "AcrPull"
assign_role "$SA_ID"  "Storage Blob Data Contributor"
assign_role "$KV_ID"  "Key Vault Secrets User"

# ---------- Verification ----------
echo "✓ Bootstrap complete:"
echo "   RG='$(STATE_RG)', SA='$(STATE_SA)', container='$(STATE_CONTAINER)'"
echo "   KV='$(KV_NAME)' (RBAC, purge-protection, PNA=$(KV_PUBLIC_NETWORK_ACCESS))"
echo "   LAW='${LAW_NAME:-<none>}'"
echo "   ACR='$(ACR_NAME)' (SKU=$(ACR_SKU), public-network=$(ACR_PUBLIC_NETWORK_ENABLED))"
