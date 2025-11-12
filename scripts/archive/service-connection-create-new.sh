#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration: UPDATE THESE VARIABLES ---
AZDO_ORG_URL="https://dev.azure.com/ExampleCorpOps"
AZDO_PROJECT_NAME="ExampleCorp"
NEW_SP_NAME="ado-oidc-sp-$(date +%s)" # Name for the new Azure AD App/SP

# This script will CREATE a connection with this name.
# It will also DELETE any old connection with this same name.
SC_NAME_TO_REPLACE="My-ARM-Connection-OIDC"

# --- Script Execution ---
echo "Fetching Azure and Azure DevOps context..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
AZDO_ORG_NAME=$(basename "$AZDO_ORG_URL")

echo "Finding ID of old Service Connection named '$SC_NAME_TO_REPLACE' to delete later..."
OLD_SC_ID=$(az devops service-endpoint list \
  --organization "$AZDO_ORG_URL" \
  --project "$AZDO_PROJECT_NAME" \
  --query "[?name=='$SC_NAME_TO_REPLACE'].id | [0]" -o tsv)

echo "Step 0: Cleaning up orphaned Service Principals from previous runs..."
ORPHANED_SP_IDS=$(az ad sp list --filter "startsWith(displayName, 'ado-oidc-sp-')" --query "[].id" -o tsv)
if [[ -n "$ORPHANED_SP_IDS" ]]; then
  for SP_ID in $ORPHANED_SP_IDS; do
    echo "  - Deleting old Service Principal with ID: $SP_ID"
    az ad sp delete --id "$SP_ID"
  done
  echo "✓ Cleanup complete."
else
  echo "✓ No orphaned Service Principals found."
fi

echo "Step 1: Creating new Azure AD Application and Service Principal: '$NEW_SP_NAME'..."
SP_JSON=$(az ad sp create-for-rbac --name "$NEW_SP_NAME" --role "Contributor" --scopes "/subscriptions/$SUBSCRIPTION_ID" --query "{appId:appId, spId:id, tenant:tenant}" -o json)
APP_ID=$(echo "$SP_JSON" | jq -r .appId)
SP_ID=$(echo "$SP_JSON" | jq -r .spId)
echo "✓ Service Principal created with App ID: $APP_ID"

echo "Step 2: Checking for existing Service Connection named '$SC_NAME_TO_REPLACE'..."
EXISTING_SC_ID=$(az devops service-endpoint list \
  --organization "$AZDO_ORG_URL" \
  --project "$AZDO_PROJECT_NAME" \
  --query "[?name=='$SC_NAME_TO_REPLACE'].id | [0]" -o tsv)

if [[ -n "$EXISTING_SC_ID" ]]; then
  echo "✓ Found existing Service Connection. Reusing ID: $EXISTING_SC_ID"
  NEW_SC_ID="$EXISTING_SC_ID"
else
  echo "No existing connection found. Creating a temporary, disabled Service Connection to reserve an ID..."
  # We create it disabled and with dummy values first to get the ID.
  # The name and isReady=false (disabled) must be in the JSON payload.
  cat > temp-sc-config.json << EOL
{
  "name": "${SC_NAME_TO_REPLACE}",
  "type": "azurerm",
  "url": "https://management.azure.com/",
  "authorization": {
    "scheme": "WorkloadIdentityFederation",
    "parameters": {
      "tenantid": "${TENANT_ID}",
      "serviceprincipalid": "${APP_ID}"
    }
  },
  "data": {
    "subscriptionId": "${SUBSCRIPTION_ID}",
    "subscriptionName": "${SUBSCRIPTION_NAME}"
  },
  "isReady": false
}
EOL

  TEMP_SC_JSON=$(az devops service-endpoint create \
    --service-endpoint-configuration ./temp-sc-config.json \
    --organization "$AZDO_ORG_URL" \
    --project "$AZDO_PROJECT_NAME" \
    --output json)

  NEW_SC_ID=$(echo "$TEMP_SC_JSON" | jq -r .id)
  echo "✓ Reserved new Service Connection ID: $NEW_SC_ID"
fi

echo "Step 3: Creating Federated Identity Credential in Azure AD..."

# Resolve Azure DevOps Organization ID (GUID) robustly using az rest.
# This requires the user to be logged in (az login) and have configured ADO (az devops login).
echo "  - Resolving Organization GUID for '$AZDO_ORG_NAME'..."
ME_ID=$(az rest \
  --method GET \
  --url "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1" \
  --resource "499b84ac-1321-427f-aa17-267ca6975798" --query id -o tsv) # ADO Resource ID

ORG_ID=$(az rest \
  --method GET \
  --url "https://app.vssps.visualstudio.com/_apis/accounts?memberId=${ME_ID}&api-version=7.1" \
  --resource "499b84ac-1321-427f-aa17-267ca6975798" \
  --query "value[?accountName=='$AZDO_ORG_NAME'].accountId | [0]" -o tsv)

if [[ -z "$ORG_ID" || "$ORG_ID" == "null" ]]; then
  echo "ERROR: Failed to resolve Azure DevOps Organization ID for '$AZDO_ORG_NAME'."
  echo "Make sure you're logged in to ADO (az devops login) and the org name is correct."
  exit 1
fi

# Construct issuer/subject for ADO OIDC
ISSUER="https://vstoken.dev.azure.com/${ORG_ID}"
SUBJECT="sc://${AZDO_ORG_NAME}/${AZDO_PROJECT_NAME}/${NEW_SC_ID}"

echo "  - Issuer: $ISSUER"
echo "  - Subject: $SUBJECT"

# Create the federated credential on the App Registration
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{\"name\":\"ado-federation\",\"issuer\":\"$ISSUER\",\"subject\":\"$SUBJECT\",\"description\":\"Azure DevOps OIDC\",\"audiences\":[\"api://AzureADTokenExchange\"]}"

echo "✓ Federated credential created successfully."

echo "Step 4: Updating the Azure DevOps Service Connection with correct details and enabling it..."
# Prepare the final configuration file
cat > sc-config.json << EOL
{
  "authorization": {
    "parameters": {
      "serviceprincipalid": "${APP_ID}",
      "tenantid": "${TENANT_ID}"
    },
    "scheme": "WorkloadIdentityFederation"
  },
  "data": {
    "subscriptionId": "${SUBSCRIPTION_ID}",
    "subscriptionName": "${SUBSCRIPTION_NAME}",
    "environment": "AzureCloud",
    "scopeLevel": "Subscription"
  },
  "name": "${SC_NAME_TO_REPLACE}",
  "type": "azurerm",
  "url": "https://management.azure.com/",
  "isReady": true,
  "isShared": false,
  "owner": "library",
  "serviceEndpointProjectReferences": [
    { "projectReference": { "id": "$(az devops project show --project "$AZDO_PROJECT_NAME" --query id -o tsv)", "name": "$AZDO_PROJECT_NAME" }, "name": "$SC_NAME_TO_REPLACE" }
  ]
}
EOL

# Use az rest for a more stable update across CLI versions
az rest \
  --method PUT \
  --url "${AZDO_ORG_URL}/${AZDO_PROJECT_NAME}/_apis/serviceendpoint/endpoints/${NEW_SC_ID}?api-version=7.1-preview.4" \
  --resource "499b84ac-1321-427f-aa17-267ca6975798" \
  --body "@sc-config.json"

# The 'enable' flag is now handled by "isReady": true in the JSON payload.
# The update command is idempotent, so we don't need to check if it's already enabled.

echo "✓ Service Connection '$SC_NAME_TO_REPLACE' is now configured and enabled."

echo "Step 5: Deleting the old, misconfigured Service Connection..."
if [[ -n "$OLD_SC_ID" ]]; then
  # Check if the old ID is different from the new/updated one before deleting
  if [[ "$OLD_SC_ID" != "$NEW_SC_ID" ]]; then
    az devops service-endpoint delete --id "$OLD_SC_ID" --organization "$AZDO_ORG_URL" --project "$AZDO_PROJECT_NAME" -y
    echo "✓ Old Service Connection with ID '$OLD_SC_ID' has been deleted."
  else
    echo "✓ In-place update performed. No separate old connection to delete."
  fi
else
  echo "✓ No old service connection with the name '$SC_NAME_TO_REPLACE' was found to delete."
fi

echo -e "\n--- Action Required ---"
echo "The programmatic recreation is complete."
echo "Update your '01-bootstrap.yaml' file with the new Service Connection ID:"
echo "OIDC_SERVICE_CONNECTION_ID: '$NEW_SC_ID'"
echo "OIDC_SERVICE_CONNECTION: '$SC_NAME_TO_REPLACE'"

# Clean up temporary files
rm -f sc-config.json temp-sc-config.json
