#!/usr/bin/env bash
set -euo pipefail

# run-powerbi-gateway.sh
# Convenience wrapper to execute powerbi_gateway.sh with default values.

ENABLE_PBI_GATEWAY=true \
PBI_RG="${PBI_RG:-rg-example-analytics}" \
PBI_LOCATION="${PBI_LOCATION:-eastus}" \
PBI_GATEWAY_NAME="${PBI_GATEWAY_NAME:-example-powerbi-gateway}" \
PBI_VNET_RG="${PBI_VNET_RG:-rg-example-core-net}" \
PBI_VNET_NAME="${PBI_VNET_NAME:-vnet-example-core}" \
PBI_SUBNET_NAME="${PBI_SUBNET_NAME:-snet-powerbi-gateway}" \
PBI_DELEGATION="${PBI_DELEGATION:-Microsoft.PowerPlatform/vnetaccesslinks}" \
PBI_GATEWAY_API_VERSION="${PBI_GATEWAY_API_VERSION:-2020-10-30-preview}" \
PBI_ENVIRONMENT_IDS="${PBI_ENVIRONMENT_IDS:-'/providers/Microsoft.PowerPlatform/locations/Na/environments/Default-00000000-0000-0000-0000-000000000000'}" \
./scripts/powerbi_gateway.sh
