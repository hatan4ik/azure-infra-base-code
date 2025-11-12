#!/usr/bin/env bash
set -euo pipefail

# ========= User-overridables =========
: "${TARGET_SUBSCRIPTION:=}"
: "${ADO_ORG:=}"
: "${ADO_ORG_URL:=https://dev.azure.com/ExampleCorpOps}"
: "${ADO_PROJECT:=ExampleCorp}"
: "${AZURE_DEVOPS_EXT_PAT:=}"

: "${RESOURCE_GROUP:=rg-ado-wif}"
: "${MI_NAME:=ado-wif-mi}"
: "${SC_NAME:=My-ARM-Connection-OIDC}"

# ========= Input validation =========
validate_inputs() {
  [[ -n "$RESOURCE_GROUP" ]] || { echo "ERROR: RESOURCE_GROUP required" >&2; exit 1; }
  [[ -n "$MI_NAME" ]] || { echo "ERROR: MI_NAME required" >&2; exit 1; }
  [[ -n "$SC_NAME" ]] || { echo "ERROR: SC_NAME required" >&2; exit 1; }
}

# ========= Ensure az devops CLI extension =========
ensure_devops_extension() {
  if ! az extension show --name azure-devops >/dev/null 2>&1; then
    echo "Installing azure-devops extension..."
    az extension add --name azure-devops >/dev/null
  fi
}

# ========= Resolve Organization URL =========
resolve_org_url() {
  if [[ -z "$ADO_ORG_URL" ]]; then
    if [[ -n "$ADO_ORG" ]]; then
      ADO_ORG_URL="https://dev.azure.com/${ADO_ORG}"
    elif [[ -n "${SYSTEM_COLLECTIONURI:-}" ]]; then
      ADO_ORG_URL="${SYSTEM_COLLECTIONURI%/}"
    else
      ADO_ORG_URL="$(az devops configure -l --query "defaults[?name=='organization'].value" -o tsv 2>/dev/null | tr -d '\r' | sed 's#/*$##' || true)"
    fi
  fi
  
  ADO_ORG_URL="${ADO_ORG_URL//$'\r'/}"
  ADO_ORG_URL="${ADO_ORG_URL%/}"
  
  if [[ -z "$ADO_ORG_URL" || "$ADO_ORG_URL" != https://dev.azure.com/* ]]; then
    echo "ERROR: Could not determine Azure DevOps organization URL." >&2
    echo "Set: export ADO_ORG_URL='https://dev.azure.com/<org>'" >&2
    exit 1
  fi
}

# ========= Resolve Project =========
resolve_project() {
  if [[ -z "$ADO_PROJECT" ]]; then
    if [[ -n "${SYSTEM_TEAMPROJECT:-}" ]]; then
      ADO_PROJECT="$SYSTEM_TEAMPROJECT"
    else
      ADO_PROJECT="$(az devops configure -l --query "defaults[?name=='project'].value" -o tsv 2>/dev/null | tr -d '\r' || true)"
      if [[ -z "$ADO_PROJECT" || "$ADO_PROJECT" == "<project>" ]]; then
        ADO_PROJECT="$(az devops project list --organization "$ADO_ORG_URL" --query "value[0].name" -o tsv 2>/dev/null || true)"
      fi
    fi
  fi
  
  if [[ -z "$ADO_PROJECT" ]]; then
    echo "ERROR: Could not determine Azure DevOps project." >&2
    echo "Set: export ADO_PROJECT='<project>'" >&2
    exit 1
  fi
}

# ========= Main execution =========
main() {
  validate_inputs
  ensure_devops_extension
  resolve_org_url
  resolve_project
  
  # ========= Authenticate DevOps CLI =========
  if [[ -n "$AZURE_DEVOPS_EXT_PAT" ]]; then
    printf '%s' "$AZURE_DEVOPS_EXT_PAT" | az devops login --organization "$ADO_ORG_URL" >/dev/null || true
  fi
  
  az devops configure --defaults organization="$ADO_ORG_URL" project="$ADO_PROJECT" >/dev/null
  
  # Sanity check access
  if ! az devops project show --organization "$ADO_ORG_URL" --project "$ADO_PROJECT" >/dev/null 2>&1; then
    echo "ERROR: Cannot access project '$ADO_PROJECT' in '$ADO_ORG_URL'" >&2
    exit 1
  fi
  echo "Info: Using Org: $ADO_ORG_URL | Project: $ADO_PROJECT"
  
  # ========= Azure subscription/tenant context =========
  if [[ -n "$TARGET_SUBSCRIPTION" ]]; then
    az account set --subscription "$TARGET_SUBSCRIPTION"
  fi
  
  SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  SUBSCRIPTION_NAME="$(az account show --query name -o tsv)"
  TENANT_ID="$(az account show --query tenantId -o tsv)"
  
  if [[ -z "$SUBSCRIPTION_ID" || -z "$TENANT_ID" ]]; then
    echo "ERROR: Unable to resolve current Azure subscription/tenant" >&2
    exit 1
  fi
  echo "Info: Azure context → Sub: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID) | Tenant: $TENANT_ID"
  
  # ========= Get Managed Identity clientId =========
  MI_CLIENT_ID="$(az identity show -g "$RESOURCE_GROUP" -n "$MI_NAME" --query clientId -o tsv 2>/dev/null || true)"
  if [[ -z "$MI_CLIENT_ID" ]]; then
    echo "ERROR: Managed Identity clientId not found for '$MI_NAME' in RG '$RESOURCE_GROUP'" >&2
    exit 1
  fi
  echo "Info: Managed Identity clientId: $MI_CLIENT_ID"
  
  # ========= Check existing Service Connection =========
  echo "Info: Checking for existing service connection named '$SC_NAME'..."
  mapfile -t SC_IDS < <(az devops service-endpoint list \
    --organization "$ADO_ORG_URL" --project "$ADO_PROJECT" \
    --query "[?name=='${SC_NAME}'].id" -o tsv 2>/dev/null || true)
  SC_ID="${SC_IDS[0]:-}"
  
  if [[ -n "$SC_ID" && ${#SC_IDS[@]} -gt 1 ]]; then
    echo "Warn: Multiple service connections named '$SC_NAME' found. Using first ID: $SC_ID"
  fi
  
  # ========= Build JSON payload =========
  JSON_FILE="$(mktemp)"
  cat > "$JSON_FILE" <<JSON
{
  "name": "${SC_NAME}",
  "type": "azurerm",
  "url": "https://management.azure.com/",
  "authorization": {
    "parameters": {
      "tenantid": "${TENANT_ID}",
      "serviceprincipalid": "${MI_CLIENT_ID}"
    },
    "scheme": "WorkloadIdentityFederation"
  },
  "data": {
    "subscriptionId": "${SUBSCRIPTION_ID}",
    "subscriptionName": "${SUBSCRIPTION_NAME}",
    "environment": "AzureCloud",
    "scopeLevel": "Subscription"
  },
  "isShared": false,
  "owner": "library"
}
JSON
  
  # ========= Create or update service connection =========
  if [[ -n "$SC_ID" ]]; then
    echo "Info: Service connection exists (ID: $SC_ID). Updating..."
    sed -i.bak '1s|^{|{"id":"'"${SC_ID}"'",|' "$JSON_FILE" && rm -f "$JSON_FILE.bak"
    az devops service-endpoint update \
      --service-endpoint-configuration "$JSON_FILE" \
      --id "$SC_ID" \
      --organization "$ADO_ORG_URL" \
      --project "$ADO_PROJECT" >/dev/null
    echo "✓ Updated WIF ARM service connection '$SC_NAME'"
  else
    echo "Info: Service connection not found. Creating..."
    az devops service-endpoint create \
      --service-endpoint-configuration "$JSON_FILE" \
      --organization "$ADO_ORG_URL" \
      --project "$ADO_PROJECT" >/dev/null
    echo "✓ Created WIF ARM service connection '$SC_NAME'"
  fi
  
  rm -f "$JSON_FILE"
}

# Execute main function
main "$@"