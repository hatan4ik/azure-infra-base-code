#!/usr/bin/env bash
# cleanup-oidc-mi-connection.sh
#
# This script cleans up an OIDC Service Connection that is linked to a User-Assigned Managed Identity.
# It performs the following actions:
# 1. Finds the Service Connection in Azure DevOps.
# 2. Extracts the 'subject' claim required for the federated credential.
# 3. Finds the corresponding federated credential on the Managed Identity and deletes it.
# 4. Deletes the Service Connection from Azure DevOps.
#
# It does NOT delete the Managed Identity itself or its role assignments.

set -euo pipefail

# --- Configuration ---
ADO_ORG_URL="${ADO_ORG_URL:-https://dev.azure.com/ExampleCorpOps}"
ADO_PROJECT="${ADO_PROJECT:-ExampleCorp}"

# The name of the Service Connection to delete.
SC_NAME="${SC_NAME:-My-ARM-Connection-OIDC}"

# The name of the User-Assigned Managed Identity.
MI_NAME="ado-wif-mi"
# The resource group where the Managed Identity is located.
MI_RESOURCE_GROUP="rg-ado-wif"
# --- End Configuration ---

echo ">> Using DevOps org: $ADO_ORG_URL | project: $ADO_PROJECT"

# Ensure az devops extension is installed and configure defaults
az extension show --name azure-devops >/dev/null 2>&1 || az extension add --name azure-devops
az devops configure --defaults organization="$ADO_ORG_URL" project="$ADO_PROJECT"

echo ">> Step 1: Searching for Service Connection named '$SC_NAME'..."
SC_INFO_JSON=$(az devops service-endpoint show --id "$(az devops service-endpoint list --query "[?name=='$SC_NAME'].id | [0]" -o tsv)" --query "{id: id, subject: authorization.parameters.subject}" -o json 2>/dev/null || echo "null")

if [[ -z "$SC_INFO_JSON" || "$SC_INFO_JSON" == "null" ]]; then
  echo "✓ Service Connection '$SC_NAME' not found. Exiting."
  exit 0
fi

SC_ID=$(echo "$SC_INFO_JSON" | jq -r .id)
FED_SUBJECT=$(echo "$SC_INFO_JSON" | jq -r .subject)

echo "   Found Service Connection with ID: $SC_ID"
echo "   Federation Subject: $FED_SUBJECT"

echo ">> Step 2: Deleting the Federated Credential from Managed Identity '$MI_NAME'..."

# Find the name of the federated credential by its subject
FED_CRED_NAME=$(az identity federated-credential list --identity-name "$MI_NAME" -g "$MI_RESOURCE_GROUP" --query "[?subject=='$FED_SUBJECT'].name | [0]" -o tsv)

if [[ -n "$FED_CRED_NAME" ]]; then
  echo "   Found federated credential '$FED_CRED_NAME'. Deleting..."
  az identity federated-credential delete --name "$FED_CRED_NAME" --identity-name "$MI_NAME" -g "$MI_RESOURCE_GROUP" --yes
  echo "✓ Federated credential deleted."
else
  echo "✓ No matching federated credential found on Managed Identity '$MI_NAME'."
fi

echo ">> Step 3: Deleting the Azure DevOps Service Connection..."
az devops service-endpoint delete --id "$SC_ID" --yes
echo "✓ Service Connection '$SC_NAME' deleted."

echo -e "\nCleanup complete."