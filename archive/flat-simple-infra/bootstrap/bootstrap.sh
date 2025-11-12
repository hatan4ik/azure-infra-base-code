#!/usr/bin/env bash
set -euo pipefail
LOCATION=${LOCATION:-eastus}
RG_NAME=${RG_NAME:-rg-tfstate}
SA_NAME=${SA_NAME:-tfstateglobal001}
CONTAINER=${CONTAINER:-tfstate}
az group create -n "$RG_NAME" -l "$LOCATION" >/dev/null
az storage account create -g "$RG_NAME" -n "$SA_NAME" -l "$LOCATION" --sku Standard_LRS >/dev/null
az storage container create --account-name "$SA_NAME" --name "$CONTAINER" --auth-mode login >/dev/null
echo "Update backend.hcl:"
echo "resource_group_name  = \"$RG_NAME\""
echo "storage_account_name = \"$SA_NAME\""
echo "container_name       = \"$CONTAINER\""
echo "key                  = \"code-runner/dev.tfstate\""
