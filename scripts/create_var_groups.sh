#!/usr/bin/env bash
set -euo pipefail

: "${SYSTEM_ACCESSTOKEN:?Enable 'Allow scripts to access the OAuth token' in pipeline settings}"

ORG_URL="${SYSTEM_COLLECTIONURI:-${SYSTEM_COLLECTIONURI:-$(System.CollectionUri)}}"
PROJECT="${SYSTEM_TEAMPROJECT:-${SYSTEM_TEAMPROJECT:-$(System.TeamProject)}}"
API_VER="7.1-preview.2"
BASE="${ORG_URL}${PROJECT}/_apis/distributedtask/variablegroups?api-version=${API_VER}"

# jq usually present on hosted ubuntu, but ensure it
if ! command -v jq >/dev/null 2>&1; then
  sudo apt-get update -y && sudo apt-get install -y jq
fi

authHdr="Authorization: Bearer ${SYSTEM_ACCESSTOKEN}"
ctype="Content-Type: application/json"

create_or_upsert_vg() {
  local name="$1"; shift
  local json="$1"; shift

  gid="$(curl -sS -H "$authHdr" "${BASE}&groupName=$(printf %s "$name" | sed 's/ /%20/g')"             | jq -r '.value[0].id // empty')"

  if [[ -n "$gid" ]]; then
    echo " - updating VG: $name (id=$gid)"
    curl -sS -X PUT -H "$authHdr" -H "$ctype"           "${ORG_URL}${PROJECT}/_apis/distributedtask/variablegroups/${gid}?api-version=${API_VER}"           -d "$json" >/dev/null
  else
    echo " - creating VG: $name"
    curl -sS -X POST -H "$authHdr" -H "$ctype"           "$BASE" -d "$json" >/dev/null
  fi
}

# vg-core-bootstrap
create_or_upsert_vg "vg-core-bootstrap" "$(cat <<'JSON'
{
  "type": "Vsts",
  "name": "vg-core-bootstrap",
  "variables": {
    "LOCATION": { "value": "eastus" },
    "STATE_RG": { "value": "rg-example-tfstate" },
    "STATE_SA": { "value": "stexampletfstate" },
    "STATE_CONTAINER": { "value": "tfstate" },
    "KV_NAME": { "value": "kv-example-platform" },
    "KV_RETENTION_DAYS": { "value": "30" },
    "KV_PUBLIC_NETWORK_ACCESS": { "value": "Disabled" },
    "LAW_NAME": { "value": "law-example-platform" },
    "LAW_SKU": { "value": "PerGB2018" },
    "ACR_NAME": { "value": "acrexampleplatform" },
    "ACR_SKU": { "value": "Premium" },
    "ACR_PUBLIC_NETWORK_ENABLED": { "value": "false" },
    "MI_RESOURCE_GROUP": { "value": "rg-ado-wif" },
    "MI_NAME": { "value": "ado-wif-mi" },
    "TAG_BusinessUnit": { "value": "core" },
    "TAG_Environment": { "value": "prod" },
    "TAG_Owner": { "value": "platform-team" },
    "TAG_CostCenter": { "value": "cc-001" },
    "TAG_System": { "value": "example-platform" },
    "TAG_Project": { "value": "example" },
    "TAG_Lifecycle": { "value": "long-lived" },
    "TAG_Contact": { "value": "devops@example.com" }
  }
}
JSON
)"

# vg-env-eastus
create_or_upsert_vg "vg-env-eastus" '{"type":"Vsts","name":"vg-env-eastus","variables":{"LOCATION":{"value":"eastus"}}}'

# vg-env-common
create_or_upsert_vg "vg-env-common" '{"type":"Vsts","name":"vg-env-common","variables":{"TAG_BusinessUnit":{"value":"core"},"TAG_Environment":{"value":"prod"},"TAG_Owner":{"value":"platform-team"},"TAG_System":{"value":"example-platform"},"TAG_Project":{"value":"example"},"TAG_Lifecycle":{"value":"long-lived"},"TAG_Contact":{"value":"devops@example.com"}}}'

# vg-core-network
create_or_upsert_vg "vg-core-network" "$(cat <<'JSON'
{
  "type":"Vsts","name":"vg-core-network",
  "variables":{
    "LOCATION":{"value":"eastus"},
    "NET_RG":{"value":"rg-example-core-net"},
    "VNET_NAME":{"value":"vnet-example-core"},
    "VNET_CIDR":{"value":"10.10.0.0/16"},
    "SNET_WORKLOADS_NAME":{"value":"snet-workloads"},
    "SNET_WORKLOADS_CIDR":{"value":"10.10.0.0/24"},
    "SNET_PE_NAME":{"value":"snet-private-endpoints"},
    "SNET_PE_CIDR":{"value":"10.10.1.0/24"},
    "Z_BLOB":{"value":"privatelink.blob.core.windows.net"},
    "Z_DFS":{"value":"privatelink.dfs.core.windows.net"},
    "Z_KV":{"value":"privatelink.vaultcore.azure.net"},
    "Z_ACR":{"value":"privatelink.azurecr.io"},
    "ENABLE_PE_KV":{"value":"false"},
    "ENABLE_PE_ACR":{"value":"false"},
    "KV_RG":{"value":"rg-example-tfstate"},
    "KV_NAME":{"value":"kv-example-platform"},
    "ACR_RG":{"value":"rg-example-tfstate"},
    "ACR_NAME":{"value":"acrexampleplatform"}
  }
}
JSON
)"

# vg-customer-washington
create_or_upsert_vg "vg-customer-washington" "$(cat <<'JSON'
{
  "type":"Vsts","name":"vg-customer-washington",
  "variables":{
    "CUSTOMER_SLUG":{"value":"washington"},
    "DATA_RG":{"value":"rg-example-data-washington"},
    "SA_NAME":{"value":""},
    "CONTAINERS_CSV":{"value":"invoices,archive"},
    "ENABLE_STORAGE_PE":{"value":"true"},
    "SITE_URL":{"value":"https://login.example.com/login"}
  }
}
JSON
)"

create_or_upsert_vg "vg-powerbi-gateway" "$(cat <<'JSON'
{
  "type":"Vsts","name":"vg-powerbi-gateway",
  "variables":{
    "ENABLE_PBI_GATEWAY":{"value":"false"},
    "PBI_RG":{"value":"rg-example-analytics"},
    "PBI_LOCATION":{"value":"eastus"},
    "PBI_GATEWAY_NAME":{"value":"example-powerbi-gateway"},
    "PBI_VNET_RG":{"value":"rg-example-core-net"},
    "PBI_VNET_NAME":{"value":"vnet-example-core"},
    "PBI_SUBNET_NAME":{"value":"snet-powerbi-gateway"},
    "PBI_SUBNET_CIDR":{"value":"10.10.3.0/27"},
    "PBI_ENVIRONMENT_IDS":{"value":""}
  }
}
JSON
)"

echo "✓ Variable groups ensured."
