#!/usr/bin/env bash
# cleanup-oidc-sc.sh
# This script deletes an OIDC/WIF service connection and its associated Azure AD resources.
set -euo pipefail

# --- Configuration ---
ADO_ORG_URL="${ADO_ORG_URL:-https://dev.azure.com/ExampleCorpOps}"
ADO_PROJECT="${ADO_PROJECT:-ExampleCorp}"
SC_NAME="${SC_NAME:-My-ARM-Connection-OIDC}"

echo ">> Using DevOps org: $ADO_ORG_URL | project: $ADO_PROJECT"

# Ensure az devops extension is installed and configure defaults
az extension show --name azure-devops >/dev/null 2>&1 || az extension add --name azure-devops
az devops configure --defaults organization="$ADO_ORG_URL" project="$ADO_PROJECT"

# --- Step 1: Find the Service Connection and its associated App ID ---
echo ">> Searching for Service Connection named '$SC_NAME'..."
SC_INFO_JSON=$(az devops service-endpoint show --id "$(az devops service-endpoint list --query "[?name=='$SC_NAME'].id | [0]" -o tsv)" --query "{id: id, appId: authorization.parameters.serviceprincipalid}" -o json 2>/dev/null || echo "null")

if [[ -z "$SC_INFO_JSON" || "$SC_INFO_JSON" == "null" ]]; then
  echo "✓ Service Connection '$SC_NAME' not found. Exiting."
  exit 0
fi

SC_ID=$(echo "$SC_INFO_JSON" | jq -r .id)
APP_ID=$(echo "$SC_INFO_JSON" | jq -r .appId)

echo "   Found Service Connection with ID: $SC_ID"
echo "   It is linked to Azure AD Application ID (Client ID): $APP_ID"

if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
    echo "!! Could not determine the Azure AD Application ID from the service connection."
    echo "   Attempting to delete the service connection only."
    az devops service-endpoint delete --id "$SC_ID" --yes
    echo "✓ Service Connection '$SC_NAME' deleted."
    exit 1
fi

# --- Step 2: Find and delete the associated Azure AD resources ---
echo ">> Searching for Service Principal associated with App ID '$APP_ID'..."
SP_INFO_JSON=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0]" -o json)

if [[ -n "$SP_INFO_JSON" && "$SP_INFO_JSON" != "null" ]]; then
  SP_ID=$(echo "$SP_INFO_JSON" | jq -r .id)
  SP_NAME=$(echo "$SP_INFO_JSON" | jq -r .displayName)
  SP_TYPE=$(echo "$SP_INFO_JSON" | jq -r .servicePrincipalType)

  if [[ "$SP_TYPE" == "ManagedIdentity" ]]; then
    echo "!! ERROR: The associated identity '$SP_NAME' is a Managed Identity, not a regular Service Principal." >&2
    echo "   This script cannot and should not delete it. To clean up this connection, please use 'cleanup-oidc-mi-connection.sh' instead." >&2
    exit 1
  fi
  echo "   Found Service Principal '$SP_NAME' with ID: $SP_ID"

  echo "   Deleting role assignments for Service Principal '$SP_ID'..."
  # The creation script assigns 'Contributor' at the subscription scope.
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  az role assignment delete --assignee "$SP_ID" --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" >/dev/null 2>&1 || echo "   - No 'Contributor' role assignment found to delete, which is okay."

  # The federated credential will be deleted when the app is deleted.

  echo "   Deleting Service Principal..."
  az ad sp delete --id "$SP_ID"
  echo "✓ Service Principal '$SP_NAME' deleted."

  echo "   Deleting associated Azure AD Application..."
  az ad app delete --id "$APP_ID"
  echo "✓ Azure AD Application '$APP_ID' deleted."
else
  echo "!! Service Principal for App ID '$APP_ID' not found. It may have been deleted already."
fi

# --- Step 3: Delete the Azure DevOps Service Connection ---
echo ">> Deleting Service Connection '$SC_NAME' (ID: $SC_ID)..."
az devops service-endpoint delete --id "$SC_ID" --yes
echo "✓ Service Connection '$SC_NAME' deleted."

echo -e "\nCleanup complete."