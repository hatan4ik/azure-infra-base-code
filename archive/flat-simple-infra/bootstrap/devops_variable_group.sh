#!/usr/bin/env bash
set -euo pipefail
AZDO_ORG_URL=${AZDO_ORG_URL:-"https://dev.azure.com/<ORG>"}; AZDO_PROJECT=${AZDO_PROJECT:-"<PROJECT>"}
VG_NAME=${VG_NAME:-"tf-backend"}; RG_NAME=${RG_NAME:-"rg-tfstate"}; SA_NAME=${SA_NAME:-"tfstateglobal001"}; CONTAINER=${CONTAINER:-"tfstate"}
az devops configure --defaults organization=$AZDO_ORG_URL project=$AZDO_PROJECT
EXISTS=$(az pipelines variable-group list --group-name "$VG_NAME" --query "[0].id" -o tsv || true)
if [ -z "$EXISTS" ]; then
  az pipelines variable-group create --name "$VG_NAME" --variables TF_RG=$RG_NAME TF_SA=$SA_NAME TF_CONTAINER=$CONTAINER >/dev/null
  echo "Created variable group '$VG_NAME'"
else
  az pipelines variable-group variable create --group-id "$EXISTS" --name TF_RG --value "$RG_NAME" >/dev/null
  az pipelines variable-group variable create --group-id "$EXISTS" --name TF_SA --value "$SA_NAME" >/dev/null
  az pipelines variable-group variable create --group-id "$EXISTS" --name TF_CONTAINER --value "$CONTAINER" >/dev/null
  echo "Updated variable group '$VG_NAME'"
fi
