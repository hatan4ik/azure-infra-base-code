#!/bin/bash
PAT="${PAT:-${AZDO_PAT:-}}"
if [[ -z "$PAT" ]]; then
  echo "Set PAT (or AZDO_PAT) to a read-scoped Azure DevOps token before running." >&2
  exit 1
fi
BASIC=$(printf ":%s" "$PAT" | base64)

ME_ID=$(curl -sS -H "Authorization: Basic $BASIC" \
  "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1" | jq -r .id)

ORG_GUID=$(curl -sS -H "Authorization: Basic $BASIC" \
  "https://app.vssps.visualstudio.com/_apis/accounts?memberId=${ME_ID}&api-version=7.1" \
  | jq -r ".value[] | select(.accountName==\"$ORG_NAME\") | .accountId")

ISSUER="https://vstoken.dev.azure.com/${ORG_GUID}"   # per spec
SUBJECT="sc://${ORG_NAME}/${PROJECT}/${SC_NAME}"     # per spec

echo "$ISSUER"
echo "$SUBJECT"
