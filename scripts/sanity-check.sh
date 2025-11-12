#!/bin/sh
ADO_ORG_URL="https://dev.azure.com/ExampleCorpOps"
ADO_PROJ="ExampleCorp"
SC_NAME="My-ARM-Connection-OIDC"

az extension add -n azure-devops >/dev/null 2>&1 || true
# If needed:
# printf '%s' "$AZURE_DEVOPS_EXT_PAT" | az devops login --organization "$ADO_ORG_URL"

SC_ID=$(az devops service-endpoint list --organization "$ADO_ORG_URL" --project "$ADO_PROJ" \
        --query "[?name=='${SC_NAME}'].id" -o tsv)
az devops service-endpoint show --organization "$ADO_ORG_URL" --project "$ADO_PROJ" --id "$SC_ID" \
  --query "{scheme:authorization.scheme, tenant:authorization.parameters.tenantid, miClientId:authorization.parameters.serviceprincipalid}" -o table
