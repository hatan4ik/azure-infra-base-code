#!/usr/bin/env bash
set -euo pipefail

customer="${CUSTOMER_SLUG:?}"
location="${LOCATION:?}"
containers_csv="${CONTAINERS_CSV:-invoices,archive}"
enable_pe="${ENABLE_STORAGE_PE:-true}"

subId="$(az account show --query id -o tsv)"
rgName="rg-example-data-${customer}"

# TAGS (data domain)
declare -a TAGS=(
  "BusinessUnit=$(TAG_BusinessUnit:-data)"
  "Environment=$(TAG_Environment:-prod)"
  "Owner=$(TAG_Owner:-platform-team)"
  "CostCenter=$(TAG_CostCenter:-cc-002)"
  "System=$(TAG_System:-example-data)"
  "Project=$(TAG_Project:-example)"
  "Lifecycle=$(TAG_Lifecycle:-long-lived)"
  "Contact=$(TAG_Contact:-devops@example.com)"
)
tag_merge(){ local rid="$1"; shift; az resource tag --ids "$rid" --is-incremental --only-show-errors --tags "$@" >/dev/null; }

# RG
az group show -n "$rgName" >/dev/null 2>&1 || az group create -n "$rgName" -l "$location" --tags "${TAGS[@]}" -o none
tag_merge "/subscriptions/${subId}/resourceGroups/${rgName}" "${TAGS[@]}"

# SA name (sticky)
prefix="st${customer}"
existing="$(az storage account list -g "$rgName" --query "[?starts_with(name, '${prefix}')].name | [0]" -o tsv)"
if [[ -n "$existing" ]]; then sa="$existing"; else suf="$(tr -dc 'a-f0-9' </dev/urandom | head -c6)"; sa="${prefix}${suf:0:6}"; fi
echo "SA=${sa}"

# SA (ADLS Gen2)
if ! az storage account show -g "$rgName" -n "$sa" >/dev/null 2>&1; then
  az storage account create -g "$rgName" -n "$sa" -l "$location" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
    --allow-blob-public-access false --https-only true --hns true \
    --tags "${TAGS[@]}" -o none
else
  saId="$(az storage account show -g "$rgName" -n "$sa" --query id -o tsv)"
  tag_merge "$saId" "${TAGS[@]}"
fi

saId="$(az storage account show -g "$rgName" -n "$sa" --query id -o tsv)"
hnsEnabled="$(az storage account show -g "$rgName" -n "$sa" --query isHnsEnabled -o tsv)"

# Containers
IFS=',' read -r -a CONTS <<< "$containers_csv"
for c in "${CONTS[@]}"; do
  name="$(echo "$c" | xargs)"; [[ -z "$name" ]] && continue
  az storage container create --name "$name" --account-name "$sa" --auth-mode login --public-access off -o none >/dev/null
done

# Diagnostics (if LAW provided)
if [[ -n "${LAW_NAME:-}" && -n "${LAW_RG:-}" ]]; then
  LAW_ID="$(az monitor log-analytics workspace show -g "$LAW_RG" -n "$LAW_NAME" --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$LAW_ID" ]]; then
    cats="$(az monitor diagnostic-settings categories list --resource "$saId" 2>/dev/null || echo '{}')"
    logs="[]"; metrics="[]"
    echo "$cats" | jq -e '.value[] | select(.type=="Log" and .name=="AuditEvent")' >/dev/null 2>&1 && logs='[{"category":"AuditEvent","enabled":true}]'
    echo "$cats" | jq -e '.value[] | select(.type=="Metric" and .name=="AllMetrics")' >/dev/null 2>&1 && metrics='[{"category":"AllMetrics","enabled":true}]'
    if az monitor diagnostic-settings list --resource "$saId" -o tsv --query "value[?name=='ds-sa'].name" | grep -q .; then
      az monitor diagnostic-settings update --name ds-sa --resource "$saId" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null
    else
      az monitor diagnostic-settings create --name ds-sa --resource "$saId" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null 2>&1 || \
      az monitor diagnostic-settings create --name ds-sa --resource "$saId" --workspace "$LAW_ID" --logs "$logs" --metrics "$metrics" >/dev/null
    fi
  fi
fi

# Harden blob service
if [[ "$hnsEnabled" == "true" ]]; then
  az storage account blob-service-properties update -g "$rgName" -n "$sa" --enable-delete-retention true --delete-retention-days 30 -o none
else
  az storage account blob-service-properties update -g "$rgName" -n "$sa" \
    --enable-delete-retention true --delete-retention-days 30 \
    --enable-versioning true \
    --enable-container-delete-retention true --container-delete-retention-days 7 -o none
fi

# RBAC (MI -> SA)
if MI_PID="$(az identity show -g "$(MI_RESOURCE_GROUP)" -n "$(MI_NAME)" --query principalId -o tsv 2>/dev/null)"; then
  az role assignment list --assignee-object-id "$MI_PID" --scope "$saId" --query "[?roleDefinitionName=='Storage Blob Data Contributor']|[0]" -o tsv | grep -q . || \
  az role assignment create --assignee-object-id "$MI_PID" --role "Storage Blob Data Contributor" --scope "$saId" -o none 2>/dev/null || \
  echo "   ! Need UA/Owner to grant RBAC on $saId"
fi

# Private Endpoints (separate for blob and dfs)
if [[ "${enable_pe,,}" == "true" ]]; then
  SUBNET_ID="/subscriptions/${subId}/resourceGroups/$(NET_RG)/providers/Microsoft.Network/virtualNetworks/$(VNET_NAME)/subnets/$(SNET_PE_NAME)"
  ZONE_BLOB_ID="/subscriptions/${subId}/resourceGroups/$(NET_RG)/providers/Microsoft.Network/privateDnsZones/$(Z_BLOB)"
  ZONE_DFS_ID="/subscriptions/${subId}/resourceGroups/$(NET_RG)/providers/Microsoft.Network/privateDnsZones/$(Z_DFS)"

  # blob
  PE_BLOB="pe-${sa}-blob"; CONN_BLOB="conn-${sa}-blob"
  az network private-endpoint show -g "$rgName" -n "$PE_BLOB" >/dev/null 2>&1 || \
  az network private-endpoint create -g "$rgName" -n "$PE_BLOB" -l "$location" \
    --subnet "$SUBNET_ID" --private-connection-resource-id "$saId" \
    --group-ids blob --connection-name "$CONN_BLOB" --tags "${TAGS[@]}" -o none
  az network private-endpoint dns-zone-group show -g "$rgName" --endpoint-name "$PE_BLOB" -n "dzg-${sa}-blob" >/dev/null 2>&1 || \
  az network private-endpoint dns-zone-group create -g "$rgName" --endpoint-name "$PE_BLOB" -n "dzg-${sa}-blob" --private-dns-zone "$ZONE_BLOB_ID" -o none

  # dfs (only if HNS=true)
  if [[ "$hnsEnabled" == "true" ]]; then
    PE_DFS="pe-${sa}-dfs"; CONN_DFS="conn-${sa}-dfs"
    az network private-endpoint show -g "$rgName" -n "$PE_DFS" >/dev/null 2>&1 || \
    az network private-endpoint create -g "$rgName" -n "$PE_DFS" -l "$location" \
      --subnet "$SUBNET_ID" --private-connection-resource-id "$saId" \
      --group-ids dfs --connection-name "$CONN_DFS" --tags "${TAGS[@]}" -o none
    az network private-endpoint dns-zone-group show -g "$rgName" --endpoint-name "$PE_DFS" -n "dzg-${sa}-dfs" >/dev/null 2>&1 || \
    az network private-endpoint dns-zone-group create -g "$rgName" --endpoint-name "$PE_DFS" -n "dzg-${sa}-dfs" --private-dns-zone "$ZONE_DFS_ID" -o none
  fi
fi

echo "✓ Customer '$customer' storage ensured (SA=$sa, HNS=$hnsEnabled)"
