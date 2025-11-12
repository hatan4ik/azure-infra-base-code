#!/usr/bin/env bash
# cleanup-admin-fc.sh
# This script deletes the resources created by admin-fc-creator.sh
set -euo pipefail

# --- Configuration: Ensure these match the values from the creation script ---
ADO_ORG_URL="${ADO_ORG_URL:-https://dev.azure.com/ExampleCorpOps}"
ADO_PROJECT="${ADO_PROJECT:-ExampleCorp}"
SC_NAME="${SC_NAME:-Azure-Admin-For-FC}"
SP_NAME="${SP_NAME:-sp-ado-admin-fc}"

echo ">> Using DevOps org: $ADO_ORG_URL | project: $ADO_PROJECT"

# Ensure az devops extension is installed and configure defaults
az extension show --name azure-devops >/dev/null 2>&1 || az extension add --name azure-devops
az devops configure --defaults organization="$ADO_ORG_URL" project="$ADO_PROJECT"

# --- Step 1: Delete the Azure DevOps Service Connection ---
echo ">> Searching for Service Connection named '$SC_NAME'..."
SC_ID=$(az devops service-endpoint list \
  --query "[?name=='$SC_NAME'].id | [0]" -o tsv)

if [[ -n "$SC_ID" ]]; then
  echo "   Found Service Connection with ID: $SC_ID. Deleting..."
  az devops service-endpoint delete --id "$SC_ID" --yes
  echo "✓ Service Connection '$SC_NAME' deleted."
else
  echo "✓ Service Connection '$SC_NAME' not found."
fi

# --- Step 2: Delete the Azure Service Principal and its associated App/Role Assignment ---
echo ">> Searching for Service Principal named '$SP_NAME'..."
SP_INFO_JSON=$(az ad sp list --display-name "$SP_NAME" --query "[0]" -o json)

if [[ -n "$SP_INFO_JSON" && "$SP_INFO_JSON" != "null" ]]; then
  SP_ID=$(echo "$SP_INFO_JSON" | jq -r .id)
  APP_ID=$(echo "$SP_INFO_JSON" | jq -r .appId)
  echo "   Found Service Principal with ID: $SP_ID"
  echo "   Associated Application ID: $APP_ID"

  echo "   Deleting role assignments for Service Principal '$SP_ID'..."
  # The role was created at the subscription scope by the original script
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  az role assignment delete --assignee "$SP_ID" --role "Owner" --scope "/subscriptions/$SUBSCRIPTION_ID" || echo "   - No 'Owner' role assignment found to delete, which is okay."

  echo "   Deleting Service Principal..."
  az ad sp delete --id "$SP_ID"
  echo "✓ Service Principal '$SP_NAME' deleted."

  echo "   Deleting associated Azure AD Application..."
  az ad app delete --id "$APP_ID"
  echo "✓ Azure AD Application '$APP_ID' deleted."

else
  echo "✓ Service Principal '$SP_NAME' not found."
fi

echo -e "\nCleanup complete."