#!/usr/bin/env bash
set -euo pipefail

# check-powerbi-gateway.sh
# Verifies the Power BI VNet gateway ARM resource exists and reports its provisioning state.
#
# Usage:
#   ./scripts/check-powerbi-gateway.sh
#
# Relies on the same environment variables used by powerbi_gateway.sh:
#   ENABLE_PBI_GATEWAY (optional guard)
#   PBI_RG, PBI_GATEWAY_NAME, PBI_GATEWAY_API_VERSION (or default)
#
# You must be logged into Azure CLI with access to the subscription (az login/az account set).

if [[ "${ENABLE_PBI_GATEWAY:-true}" != "true" ]]; then
  echo "ENABLE_PBI_GATEWAY is not 'true'; nothing to check."
  exit 0
fi

# Allow reading from azure-pipelines default variable names if not set locally
PBI_RG="${PBI_RG:-rg-example-analytics}"
PBI_GATEWAY_NAME="${PBI_GATEWAY_NAME:-example-powerbi-gateway}"
PBI_GATEWAY_API_VERSION="${PBI_GATEWAY_API_VERSION:-2020-10-30-preview}"

SUB_ID="$(az account show --query id -o tsv)"
RESOURCE_ID="/subscriptions/${SUB_ID}/resourceGroups/${PBI_RG}/providers/Microsoft.PowerPlatform/vnetGateways/${PBI_GATEWAY_NAME}"

echo ">> Checking Power BI VNet gateway ${RESOURCE_ID}"
if ! az rest --method get --url "https://management.azure.com${RESOURCE_ID}?api-version=${PBI_GATEWAY_API_VERSION}" >/tmp/pbi_gateway_check.json 2>/tmp/pbi_gateway_check.err; then
  cat /tmp/pbi_gateway_check.err >&2
  echo "ERROR: Unable to query the gateway. Validate permissions, resource group, and API version." >&2
  exit 1
fi

STATE="$(jq -r '.properties.provisioningState' /tmp/pbi_gateway_check.json)"
ENVS="$(jq -r '.properties.associatedEnvironments[].id' /tmp/pbi_gateway_check.json 2>/dev/null || true)"

echo "ProvisioningState: ${STATE:-unknown}"
if [[ -n "${ENVS}" ]]; then
  echo "Associated environments:"
  echo "${ENVS}" | sed 's/^/  - /'
else
  echo "Associated environments: (none reported)"
fi

rm -f /tmp/pbi_gateway_check.json /tmp/pbi_gateway_check.err
