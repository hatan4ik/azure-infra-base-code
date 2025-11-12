#!/usr/bin/env bash
set -euo pipefail

if [[ "${ENABLE_PBI_GATEWAY:-false}" != "true" ]]; then
  echo "ENABLE_PBI_GATEWAY flag is not 'true'; skipping Power BI VNet gateway provisioning."
  exit 0
fi

: "${PBI_RG:?PBI_RG env var must be set}"
: "${PBI_LOCATION:?PBI_LOCATION env var must be set}"
: "${PBI_GATEWAY_NAME:?PBI_GATEWAY_NAME env var must be set}"
: "${PBI_VNET_RG:?PBI_VNET_RG env var must be set}"
: "${PBI_VNET_NAME:?PBI_VNET_NAME env var must be set}"
: "${PBI_SUBNET_NAME:?PBI_SUBNET_NAME env var must be set}"
: "${PBI_DELEGATION:=Microsoft.PowerPlatform/vnetaccesslinks}"

# Accept either explicit IDs or admin-center URLs (comma-separated)
ENVIRONMENT_IDS_VALUE=""
if [[ -n "${PBI_ENVIRONMENT_IDS:-}" ]]; then
  ENVIRONMENT_IDS_VALUE="${PBI_ENVIRONMENT_IDS}"
elif [[ -n "${PBI_ENVIRONMENT_LINKS:-}" ]]; then
  IFS=',' read -r -a _links <<< "${PBI_ENVIRONMENT_LINKS}"
  for raw in "${_links[@]}"; do
    link="$(echo "$raw" | xargs)"
    [[ -z "$link" ]] && continue
    envName="$(echo "$link" | sed -n 's#.*/environments/\([^/?]*\).*#\1#p')"
    geo="$(echo "$link" | sed -n 's/.*[?&]geo=\([^&]*\).*/\1/p')"
    if [[ -n "$envName" && -n "$geo" ]]; then
      id="/providers/Microsoft.PowerPlatform/locations/${geo}/environments/${envName}"
      if [[ -n "$ENVIRONMENT_IDS_VALUE" ]]; then
        ENVIRONMENT_IDS_VALUE="${ENVIRONMENT_IDS_VALUE},${id}"
      else
        ENVIRONMENT_IDS_VALUE="$id"
      fi
    fi
  done
fi

if [[ -z "${ENVIRONMENT_IDS_VALUE}" ]]; then
  echo "No Power Platform environment identifiers supplied; skipping Power BI VNet gateway provisioning."
  exit 0
fi

PBI_ENVIRONMENT_IDS="${ENVIRONMENT_IDS_VALUE}"

command -v jq >/dev/null 2>&1 || { sudo apt-get update -y && sudo apt-get install -y jq; }

SUB_ID="$(az account show --query id -o tsv)"
echo ">> Subscription: $(az account show --query '{name:name,id:id,tenant:tenantId}' -o tsv)"

VNET_ID="/subscriptions/${SUB_ID}/resourceGroups/${PBI_VNET_RG}/providers/Microsoft.Network/virtualNetworks/${PBI_VNET_NAME}"
SUBNET_ID="${VNET_ID}/subnets/${PBI_SUBNET_NAME}"
RESOURCE_ID="/subscriptions/${SUB_ID}/resourceGroups/${PBI_RG}/providers/Microsoft.PowerPlatform/vnetGateways/${PBI_GATEWAY_NAME}"
API_VERSION="${PBI_GATEWAY_API_VERSION:-2020-10-30-preview}"

echo ">> Validating delegated subnet ${SUBNET_ID}"
if ! az network vnet subnet show -g "${PBI_VNET_RG}" --vnet-name "${PBI_VNET_NAME}" -n "${PBI_SUBNET_NAME}" >/dev/null 2>&1; then
  echo "ERROR: Subnet ${PBI_SUBNET_NAME} not found in ${PBI_VNET_NAME}. Run vnet provisioning first." >&2
  exit 1
fi

delegated="$(az network vnet subnet show -g "${PBI_VNET_RG}" --vnet-name "${PBI_VNET_NAME}" -n "${PBI_SUBNET_NAME}" \
  --query "delegations[?serviceName=='${PBI_DELEGATION}'] | length(@)" -o tsv 2>/dev/null || echo 0)"
if [[ "${delegated}" -eq 0 ]]; then
  echo "ERROR: Subnet ${PBI_SUBNET_NAME} is not delegated to ${PBI_DELEGATION}." >&2
  exit 1
fi

delegated="$(az network vnet subnet show -g "${PBI_VNET_RG}" --vnet-name "${PBI_VNET_NAME}" -n "${PBI_SUBNET_NAME}" \
  --query "delegations[?serviceName=='${PBI_DELEGATION}'] | length(@)" -o tsv 2>/dev/null || echo 0)"
if [[ "${delegated}" -eq 0 ]]; then
  echo "ERROR: Subnet ${PBI_SUBNET_NAME} is not delegated to ${PBI_DELEGATION}." >&2
  exit 1
fi

echo ">> Ensuring resource group ${PBI_RG}"
if ! az group show -n "${PBI_RG}" >/dev/null 2>&1; then
  az group create -n "${PBI_RG}" -l "${PBI_LOCATION}" -o none
fi

echo ">> Registering resource provider Microsoft.PowerPlatform"
az provider register --namespace Microsoft.PowerPlatform >/dev/null
state="Unknown"
for _ in {1..12}; do
  state="$(az provider show --namespace Microsoft.PowerPlatform --query registrationState -o tsv 2>/dev/null || echo 'Unknown')"
  [[ "$state" == "Registered" ]] && break
  echo "   - Provider state: $state (waiting up to $((12-_)) more checks)"
  sleep 10
done
if [[ "$state" != "Registered" ]]; then
  echo "ERROR: Microsoft.PowerPlatform provider registration incomplete (state=${state})." >&2
  exit 1
fi

ENV_ASSOC="$(python3 - <<'PY' "${PBI_ENVIRONMENT_IDS}"
import sys, json
ids = [item.strip() for item in sys.argv[1].split(',') if item.strip()]
if not ids:
    sys.stderr.write("ERROR: No environment IDs provided via PBI_ENVIRONMENT_IDS.\n")
    sys.exit(1)
print(json.dumps([{"id": env_id} for env_id in ids]))
PY
)"

echo ">> Upserting VNet data gateway ${PBI_GATEWAY_NAME} in ${PBI_LOCATION}"
payload="$(jq -n \
  --arg location "${PBI_LOCATION}" \
  --arg vnet "${VNET_ID}" \
  --arg subnet "${SUBNET_ID}" \
  --argjson envs "${ENV_ASSOC}" \
  '{ location: $location, properties: { virtualNetwork: { id: $vnet }, subnet: { id: $subnet }, associatedEnvironments: $envs } }')"

az rest --method put \
  --url "https://management.azure.com${RESOURCE_ID}?api-version=${API_VERSION}" \
  --body "${payload}" >/dev/null

echo ">> Confirming provisioning state"
status="$(az rest --method get \
  --url "https://management.azure.com${RESOURCE_ID}?api-version=${API_VERSION}" \
  --query "properties.provisioningState" -o tsv 2>/dev/null || true)"

echo "✓ Power BI VNet gateway ensured (provisioningState=${status:-unknown})."
