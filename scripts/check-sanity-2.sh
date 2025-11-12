ORG_URL="https://dev.azure.com/ExampleCorpOps"
PROJ_NAME="ExampleCorp"

az extension show --name azure-devops >/dev/null 2>&1 || az extension add --name azure-devops
echo "$AZDO_PAT" | az devops login --organization "$ORG_URL" >/dev/null 2>&1 || true
az devops configure --defaults organization="$ORG_URL" project="$PROJ_NAME"

FOUND_ID=$(az devops service-endpoint list \
  --query "[?name=='My-ARM-Connection-OIDC'].id | [0]" -o tsv)

echo "SC name → GUID: $FOUND_ID"
