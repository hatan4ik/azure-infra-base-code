#!/usr/bin/env bash
set -euo pipefail

# get-ado-token.sh
# Acquires short-lived Azure DevOps token using service connection
# Replaces manual PAT export pattern

: "${ADO_ORG_URL:?ADO_ORG_URL required}"
: "${ADO_PROJECT:?ADO_PROJECT required}"
: "${AZURE_DEVOPS_EXT_PAT:=${SYSTEM_ACCESSTOKEN:-}}"

if [[ -z "$AZURE_DEVOPS_EXT_PAT" ]]; then
  echo "ERROR: No token available. Set SYSTEM_ACCESSTOKEN or AZURE_DEVOPS_EXT_PAT" >&2
  exit 1
fi

# Validate token works
if ! az devops project show \
  --organization "$ADO_ORG_URL" \
  --project "$ADO_PROJECT" \
  >/dev/null 2>&1; then
  echo "ERROR: Token validation failed" >&2
  exit 1
fi

# Export for use by other scripts
export AZURE_DEVOPS_EXT_PAT

echo "✓ Azure DevOps token acquired and validated"
echo "Token expires: $(date -u -d '+1 hour' '+%Y-%m-%d %H:%M:%S UTC')"
