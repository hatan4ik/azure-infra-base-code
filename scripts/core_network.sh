#!/usr/bin/env bash
set -euo pipefail

# ========= Input validation =========
validate_required_vars() {
  local missing=()
  for var in NET_RG VNET_NAME VNET_CIDR SNET_WORKLOADS_NAME SNET_WORKLOADS_CIDR SNET_PE_NAME SNET_PE_CIDR LOCATION; do
    [[ -n "${!var:-}" ]] || missing+=("$var")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required variables: ${missing[*]}" >&2
    exit 1
  fi
}

# ========= Ensure dependencies =========
ensure_dependencies() {
  command -v jq >/dev/null 2>&1 || { sudo apt-get update -y && sudo apt-get install -y jq; }
  command -v python3 >/dev/null 2>&1 || { sudo apt-get update -y && sudo apt-get install -y python3-minimal; }
  command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI not found" >&2; exit 1; }
}

validate_required_vars
ensure_dependencies

SUB_ID="$(az account show --query id -o tsv)"

declare -a TAGS=(
  "BusinessUnit=${TAG_BusinessUnit:-core}"
  "Environment=${TAG_Environment:-prod}"
  "Owner=${TAG_Owner:-platform-team}"
  "System=${TAG_System:-example-platform}"
  "Project=${TAG_Project:-example}"
  "Lifecycle=${TAG_Lifecycle:-long-lived}"
  "Contact=${TAG_Contact:-devops@example.com}"
)

tag_merge(){ az resource tag --ids "$1" --is-incremental --only-show-errors --tags "${TAGS[@]}" >/dev/null; }

# RG
if ! az group show -n "${NET_RG}" >/dev/null 2>&1; then
  az group create -n "${NET_RG}" -l "${LOCATION}" --tags "${TAGS[@]}" -o none
else
  tag_merge "/subscriptions/${SUB_ID}/resourceGroups/${NET_RG}"
fi

py_contains() {
  python3 - "$1" "$2" <<'PY'
import sys, ipaddress
s, n = sys.argv[1], sys.argv[2]
print(str(ipaddress.ip_network(n).subnet_of(ipaddress.ip_network(s))).lower())
PY
}
py_two_children() {
  python3 - "$1" <<'PY'
import sys, ipaddress
b=ipaddress.ip_network(sys.argv[1]); p=min(max(b.prefixlen+1,24), b.max_prefixlen)
k=list(b.subnets(new_prefix=p))
while len(k)<2 and p<b.max_prefixlen:
    p+=1; k=list(b.subnets(new_prefix=p))
print(str(k[0]), str(k[1]))
PY
}

# VNet
if ! az network vnet show -g "${NET_RG}" -n "${VNET_NAME}" >/dev/null 2>&1; then
  az network vnet create -g "${NET_RG}" -n "${VNET_NAME}" -l "${LOCATION}" --address-prefixes "${VNET_CIDR}" -o none
fi
mapfile -t CUR_SPACES < <(az network vnet show -g "${NET_RG}" -n "${VNET_NAME}" --query 'addressSpace.addressPrefixes[]' -o tsv)

ensure_space_present() {
  local want="$1"; local found="false"
  for p in "${CUR_SPACES[@]:-}"; do [[ "$p" == "$want" ]] && found="true" && break; done
  if [[ "$found" == "false" ]]; then
    local all=( "${CUR_SPACES[@]:-}" ); all+=( "$want" )
    az network vnet update -g "${NET_RG}" -n "${VNET_NAME}" --address-prefixes "${all[@]}" -o none
    mapfile -t CUR_SPACES < <(az network vnet show -g "${NET_RG}" -n "${VNET_NAME}" --query 'addressSpace.addressPrefixes[]' -o tsv)
  fi
}

fits_in_any(){ local n="$1"; for p in "${CUR_SPACES[@]:-}"; do [[ "$(py_contains "$p" "$n")" == "true" ]] && return 0; done; return 1; }

REQ_W_CIDR="${SNET_WORKLOADS_CIDR}"
REQ_PE_CIDR="${SNET_PE_CIDR}"
if ! fits_in_any "$REQ_W_CIDR" || ! fits_in_any "$REQ_PE_CIDR"; then ensure_space_present "${VNET_CIDR}"; fi
if ! fits_in_any "$REQ_W_CIDR" || ! fits_in_any "$REQ_PE_CIDR"; then
  BASE="${CUR_SPACES[0]}"; read -r NEW_W NEW_PE < <(py_two_children "$BASE")
  REQ_W_CIDR="$NEW_W"; REQ_PE_CIDR="$NEW_PE"
fi

# Subnets
if ! az network vnet subnet show -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${SNET_WORKLOADS_NAME}" >/dev/null 2>&1; then
  az network vnet subnet create -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${SNET_WORKLOADS_NAME}" --address-prefixes "$REQ_W_CIDR" -o none
else
  az network vnet subnet update -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${SNET_WORKLOADS_NAME}" --address-prefixes "$REQ_W_CIDR" -o none || true
fi

if ! az network vnet subnet show -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${SNET_PE_NAME}" >/dev/null 2>&1; then
  az network vnet subnet create -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${SNET_PE_NAME}" --address-prefixes "$REQ_PE_CIDR" --private-endpoint-network-policies Disabled -o none
else
  az network vnet subnet update -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${SNET_PE_NAME}" --address-prefixes "$REQ_PE_CIDR" --private-endpoint-network-policies Disabled -o none || true
fi

VNET_ID="$(az network vnet show -g "${NET_RG}" -n "${VNET_NAME}" --query id -o tsv)"

# Private DNS + links
ensure_zone_and_link () {
  local zone="$1"; [[ -z "$zone" ]] && return 0
  if ! az network private-dns zone show -g "${NET_RG}" -n "$zone" >/dev/null 2>&1; then
    az network private-dns zone create -g "${NET_RG}" -n "$zone" -o none
  fi
  local link="ln-${VNET_NAME}-${zone//./-}"
  if ! az network private-dns link vnet show -g "${NET_RG}" -z "$zone" -n "$link" >/dev/null 2>&1; then
    az network private-dns link vnet create -g "${NET_RG}" -z "$zone" -n "$link" -v "$VNET_ID" -e false -o none
  fi
}
for z in "${Z_BLOB}" "${Z_DFS}" "${Z_KV}" "${Z_ACR}"; do ensure_zone_and_link "$z"; done

# Optional PE for KV/ACR
create_pe () {
  local name="$1" rid="$2" gid="$3" conn="$4"
  if ! az network private-endpoint show -g "${NET_RG}" -n "$name" >/dev/null 2>&1; then
    az network private-endpoint create -g "${NET_RG}" -n "$name" -l "${LOCATION}"           --vnet-name "${VNET_NAME}" --subnet "${SNET_PE_NAME}"           --private-connection-resource-id "$rid" --group-ids "$gid"           --connection-name "$conn" -o none
  fi
}
create_dzg () {
  local pe="$1" zone="$2" dzg="$3"
  if ! az network private-endpoint dns-zone-group show -g "${NET_RG}" --endpoint-name "$pe" -n "$dzg" >/dev/null 2>&1; then
    az network private-endpoint dns-zone-group create -g "${NET_RG}" --endpoint-name "$pe" -n "$dzg"           --private-dns-zone "/subscriptions/${SUB_ID}/resourceGroups/${NET_RG}/providers/Microsoft.Network/privateDnsZones/${zone}" -o none
  fi
}

if [[ "${ENABLE_PE_KV}" == "true" ]] && az keyvault show -g "${KV_RG}" -n "${KV_NAME}" >/dev/null 2>&1; then
  KV_ID="$(az keyvault show -g "${KV_RG}" -n "${KV_NAME}" --query id -o tsv)"
  create_pe  "pe-${KV_NAME}-kv" "$KV_ID" "vault"  "conn-${KV_NAME}-kv"
  create_dzg "pe-${KV_NAME}-kv" "${Z_KV}" "dzg-${KV_NAME}-kv"
fi
if [[ "${ENABLE_PE_ACR}" == "true" ]] && az acr show -g "${ACR_RG}" -n "${ACR_NAME}" >/dev/null 2>&1; then
  ACR_ID="$(az acr show -g "${ACR_RG}" -n "${ACR_NAME}" --query id -o tsv)"
  create_pe  "pe-${ACR_NAME}-acr" "$ACR_ID" "registry" "conn-${ACR_NAME}-acr"
  create_dzg "pe-${ACR_NAME}-acr" "${Z_ACR}" "dzg-${ACR_NAME}-acr"
fi

echo "✓ Core network ensured."
