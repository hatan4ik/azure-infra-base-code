#!/usr/bin/env bash
set -euo pipefail

# list-powerbi-environments.sh
# Lists Power Platform environment resource IDs for the current tenant.
# Usage:
#   ./scripts/list-powerbi-environments.sh            # list all regions
#   ./scripts/list-powerbi-environments.sh westus2    # filter to a specific region

REGION_FILTER="${1:-}"
PROVIDER="Microsoft.BusinessAppPlatform"
API_VERSION="2018-07-01-preview"

URL="https://management.azure.com/providers/${PROVIDER}/environments?api-version=${API_VERSION}"

echo ">> Querying Power Platform environments (${REGION_FILTER:-all regions}) using provider ${PROVIDER}"
if ! OUTPUT="$(az rest --method get --url "$URL" 2>/dev/null)"; then
  echo "ERROR: Unable to query environments via ${PROVIDER}. Ensure your account has Power Platform admin rights and the provider is available in this tenant." >&2
  exit 1
fi

echo "$OUTPUT" | jq -r '.value[] | [.properties.displayName, .properties.location, .id] | @tsv' |
  awk -v regionFilter="${REGION_FILTER}" '
    BEGIN {
      printf "%-40s\t%-15s\t%s\n","DisplayName","Region","ResourceId"
      print "-------------------------------------------------------------------------------"
    }
    {
      if (regionFilter == "" || tolower($2) == tolower(regionFilter)) {
        printf "%-40s\t%-15s\t%s\n",$1,$2,$3
      }
    }'
