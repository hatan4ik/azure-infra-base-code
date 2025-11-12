#!/bin/bash
# inputs you know
ORG_NAME="ExampleCorpOps"          # e.g., simdream
PROJECT="ExampleCorp"           # e.g., infra
SC_NAME="ado-wif-mi"             # service connection display name

# DevOps resource ID for az rest (gets an AAD token for Azure DevOps)
ADO_RES="499b84ac-1321-427f-aa17-267ca6975798"

# 1) Who am I (in ADO)?
ME_ID=$(az rest -m GET \
  -u "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1" \
  --resource $ADO_RES --query id -o tsv)

# 2) Find the org GUID (aka accountId) for ORG_NAME
ORG_GUID=$(az rest -m GET \
  -u "https://app.vssps.visualstudio.com/_apis/accounts?memberId=${ME_ID}&api-version=7.1" \
  --resource $ADO_RES \
  --query "value[?accountName=='${ORG_NAME}'].accountId | [0]" -o tsv)

# 3) Build Issuer + Subject
ADO_OIDC_ISSUER="https://vstoken.dev.azure.com/${ORG_GUID}"
ADO_OIDC_SUBJECT="sc://${ORG_NAME}/${PROJECT}/${SC_NAME}"

echo "ISSUER : $ADO_OIDC_ISSUER"
echo "SUBJECT: $ADO_OIDC_SUBJECT"

