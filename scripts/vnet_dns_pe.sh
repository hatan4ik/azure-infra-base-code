#!/usr/bin/env bash
# vnet_dns_pe.sh — Core VNet + subnets + Private DNS zones (+ optional KV/ACR PEs)
# Idempotent. Uses Bash-style variable expansion (NOT ADO's $(VAR) syntax).

set -euo pipefail

# --------- Inputs with sane defaults (override via env from the pipeline) ----------
LOCATION="${LOCATION:-eastus}"

NET_RG="${NET_RG:?NET_RG env var must be set}"
VNET_NAME="${VNET_NAME:-vnet-example-core}"
VNET_CIDR="${VNET_CIDR:-10.10.0.0/16}"

SNET_WORKLOADS_NAME="${SNET_WORKLOADS_NAME:-snet-workloads}"
SNET_WORKLOADS_CIDR="${SNET_WORKLOADS_CIDR:-10.10.0.0/24}"
SNET_PE_NAME="${SNET_PE_NAME:-snet-private-endpoints}"
SNET_PE_CIDR="${SNET_PE_CIDR:-10.10.1.0/24}"

# Private DNS
Z_BLOB="${Z_BLOB:-privatelink.blob.core.windows.net}"
Z_DFS="${Z_DFS:-privatelink.dfs.core.windows.net}"
Z_KV="${Z_KV:-privatelink.vaultcore.azure.net}"
Z_ACR="${Z_ACR:-privatelink.azurecr.io}"

# Optional PEs for shared services
ENABLE_PE_KV="${ENABLE_PE_KV:-false}"
ENABLE_PE_ACR="${ENABLE_PE_ACR:-false}"
KV_RG="${KV_RG:-rg-example-tfstate}"
KV_NAME="${KV_NAME:-kv-example-platform}"
ACR_RG="${ACR_RG:-rg-example-tfstate}"
ACR_NAME="${ACR_NAME:-acrexampleplatform}"

# Optional Power BI VNet gateway subnet
ENABLE_PBI_GATEWAY="${ENABLE_PBI_GATEWAY:-false}"
PBI_SUBNET_NAME="${PBI_SUBNET_NAME:-snet-powerbi-gateway}"
PBI_SUBNET_CIDR="${PBI_SUBNET_CIDR:-10.10.3.0/27}"
PBI_DELEGATION="${PBI_DELEGATION:-Microsoft.PowerPlatform/vnetaccesslinks}"

# Tags (key=value pairs for az --tags)
TAG_BusinessUnit="${TAG_BusinessUnit:-core}"
TAG_Environment="${TAG_Environment:-prod}"
TAG_Owner="${TAG_Owner:-platform-team}"
TAG_System="${TAG_System:-example-platform}"
TAG_Project="${TAG_Project:-example}"
TAG_Lifecycle="${TAG_Lifecycle:-long-lived}"
TAG_Contact="${TAG_Contact:-devops@example.com}"

TAGS=(
  "BusinessUnit=${TAG_BusinessUnit}"
  "Environment=${TAG_Environment}"
  "Owner=${TAG_Owner}"
  "System=${TAG_System}"
  "Project=${TAG_Project}"
  "Lifecycle=${TAG_Lifecycle}"
  "Contact=${TAG_Contact}"
)

echo "> Subscription:"
az account show --query "{name:name,id:id,tenantId:tenantId}" -o tsv | awk '{printf "  - %s (%s) tenant=%s\n",$1,$2,$3}'
SUB_ID="$(az account show --query id -o tsv)"

tag_merge() {  # resource ID + tags...
  local rid="$1"; shift
  az resource tag --ids "$rid" --is-incremental --only-show-errors --tags "$@" >/dev/null
}

# ---------- RG ----------
echo ">> Ensure network RG ${NET_RG}"
if ! az group show -n "${NET_RG}" >/dev/null 2>&1; then
  az group create -n "${NET_RG}" -l "${LOCATION}" --tags "${TAGS[@]}" -o none
else
  tag_merge "/subscriptions/${SUB_ID}/resourceGroups/${NET_RG}" "${TAGS[@]}"
fi

# ---------- Helpers (CIDR logic) ----------
py_contains() {
  # args: <supernet> <subnet> -> prints true/false
  python3 - <<'PY' "$1" "$2"
import sys, ipaddress
sup = ipaddress.ip_network(sys.argv[1], strict=False)
sub = ipaddress.ip_network(sys.argv[2], strict=False)
print(str(sub.subnet_of(sup)).lower())
PY
}

py_two_children() {
  # arg: <base_cidr> -> prints two child subnets "x/y a/b" (ensure at least /24)
  python3 - <<'PY' "$1"
import sys, ipaddress
b = ipaddress.ip_network(sys.argv[1], strict=False)
p = max(b.prefixlen + 1, 24)
while True:
    kids = list(b.subnets(new_prefix=p))
    if len(kids) >= 2 or p >= b.max_prefixlen:
        break
    p += 1
print(str(kids[0]), str(kids[1]))
PY
}

# ---------- VNet + Subnets ----------
echo ">> Ensure VNet + subnets"
if ! az network vnet show -g "${NET_RG}" -n "${VNET_NAME}" >/dev/null 2>&1; then
  az network vnet create -g "${NET_RG}" -n "${VNET_NAME}" -l "${LOCATION}" \
    --address-prefixes "${VNET_CIDR}" -o none
fi

# Current address spaces
mapfile -t CUR_SPACES < <(az network vnet show -g "${NET_RG}" -n "${VNET_NAME}" --query 'addressSpace.addressPrefixes[]' -o tsv)

ensure_space_present() {
  local want="$1"
  local found="false"
  for p in "${CUR_SPACES[@]:-}"; do
    [[ "$p" == "$want" ]] && found="true" && break
  done
  if [[ "$found" == "false" ]]; then
    local all=( "${CUR_SPACES[@]:-}" ); all+=( "$want" )
    az network vnet update -g "${NET_RG}" -n "${VNET_NAME}" --address-prefixes "${all[@]}" -o none
    mapfile -t CUR_SPACES < <(az network vnet show -g "${NET_RG}" -n "${VNET_NAME}" --query 'addressSpace.addressPrefixes[]' -o tsv)
  fi
}

fits_in_any() {
  local subnet="$1"
  for p in "${CUR_SPACES[@]:-}"; do
    if [[ "$(py_contains "$p" "$subnet")" == "true" ]]; then
      return 0
    fi
  done
  return 1
}

REQ_W_CIDR="${SNET_WORKLOADS_CIDR}"
REQ_PE_CIDR="${SNET_PE_CIDR}"

if ! fits_in_any "$REQ_W_CIDR" || ! fits_in_any "$REQ_PE_CIDR"; then
  ensure_space_present "${VNET_CIDR}"
fi
if ! fits_in_any "$REQ_W_CIDR" || ! fits_in_any "$REQ_PE_CIDR"; then
  if [[ ${#CUR_SPACES[@]} -eq 0 ]]; then
    echo "ERROR: VNet has no addressSpace after update attempt." >&2
    exit 1
  fi
  BASE="${CUR_SPACES[0]}"
  read -r NEW_W NEW_PE < <(py_two_children "$BASE")
  echo "   ! Requested subnets don't fit in current VNet spaces. Re-basing in ${BASE}:"
  echo "     - ${SNET_WORKLOADS_NAME}: ${REQ_W_CIDR} -> ${NEW_W}"
  echo "     - ${SNET_PE_NAME}:       ${REQ_PE_CIDR} -> ${NEW_PE}"
  REQ_W_CIDR="$NEW_W"
  REQ_PE_CIDR="$NEW_PE"
fi

# Create/update subnets with final CIDRs
if ! az network vnet subnet show -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${SNET_WORKLOADS_NAME}" >/dev/null 2>&1; then
  az network vnet subnet create -g "${NET_RG}" --vnet-name "${VNET_NAME}" \
    -n "${SNET_WORKLOADS_NAME}" --address-prefixes "$REQ_W_CIDR" -o none
else
  az network vnet subnet update -g "${NET_RG}" --vnet-name "${VNET_NAME}" \
    -n "${SNET_WORKLOADS_NAME}" --address-prefixes "$REQ_W_CIDR" -o none || true
fi

if ! az network vnet subnet show -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${SNET_PE_NAME}" >/dev/null 2>&1; then
  az network vnet subnet create -g "${NET_RG}" --vnet-name "${VNET_NAME}" \
    -n "${SNET_PE_NAME}" --address-prefixes "$REQ_PE_CIDR" \
    --private-endpoint-network-policies Disabled -o none
else
  az network vnet subnet update -g "${NET_RG}" --vnet-name "${VNET_NAME}" \
    -n "${SNET_PE_NAME}" --address-prefixes "$REQ_PE_CIDR" \
    --private-endpoint-network-policies Disabled -o none || true
fi

if [[ "$ENABLE_PBI_GATEWAY" == "true" ]]; then
  echo ">> Ensure Power BI gateway subnet ${PBI_SUBNET_NAME}"
  if ! fits_in_any "$PBI_SUBNET_CIDR"; then
    echo "ERROR: PBI_SUBNET_CIDR=${PBI_SUBNET_CIDR} is not contained within VNet address space. Adjust config." >&2
    exit 1
  fi

  if ! az network vnet subnet show -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${PBI_SUBNET_NAME}" >/dev/null 2>&1; then
    az network vnet subnet create -g "${NET_RG}" --vnet-name "${VNET_NAME}" \
      -n "${PBI_SUBNET_NAME}" --address-prefixes "${PBI_SUBNET_CIDR}" \
      --delegations "${PBI_DELEGATION}" -o none
  else
    az network vnet subnet update -g "${NET_RG}" --vnet-name "${VNET_NAME}" \
      -n "${PBI_SUBNET_NAME}" --address-prefixes "${PBI_SUBNET_CIDR}" \
      --delegations "${PBI_DELEGATION}" -o none || true
  fi

  # Ensure delegation present (update may no-op if same prefix but no delegation)
  if ! az network vnet subnet show -g "${NET_RG}" --vnet-name "${VNET_NAME}" -n "${PBI_SUBNET_NAME}" \
      --query "delegations[?serviceName=='${PBI_DELEGATION}'] | [0]" -o tsv | grep -q .; then
    az network vnet subnet update -g "${NET_RG}" --vnet-name "${VNET_NAME}" \
      -n "${PBI_SUBNET_NAME}" --delegations "${PBI_DELEGATION}" -o none
  fi
fi

VNET_ID="$(az network vnet show -g "${NET_RG}" -n "${VNET_NAME}" --query id -o tsv)"

# ---------- Private DNS zones + links ----------
echo ">> Ensure Private DNS zones + VNet links"
ensure_zone_and_link () {
  local zone="${1-}"
  [[ -z "$zone" ]] && { echo "   ! zone empty; skip"; return 0; }
  if ! az network private-dns zone show -g "${NET_RG}" -n "$zone" >/dev/null 2>&1; then
    az network private-dns zone create -g "${NET_RG}" -n "$zone" -o none
  fi
  local link="ln-${VNET_NAME}-${zone//./-}"
  if ! az network private-dns link vnet show -g "${NET_RG}" -z "$zone" -n "$link" >/dev/null 2>&1; then
    az network private-dns link vnet create -g "${NET_RG}" -z "$zone" -n "$link" \
      -v "$VNET_ID" -e false -o none
  fi
}
ensure_zone_and_link "${Z_BLOB}"
ensure_zone_and_link "${Z_DFS}"
ensure_zone_and_link "${Z_KV}"
ensure_zone_and_link "${Z_ACR}"

# ---------- Optional Private Endpoints for shared services ----------
echo ">> Optional: PEs + DNS zone groups"
create_pe () {
  local name="${1-}"; local rid="${2-}"; local group="${3-}"; local conn="${4-}"
  [[ -z "$name" || -z "$rid" || -z "$group" || -z "$conn" ]] && { echo "   ! create_pe: missing args — skip"; return 0; }
  if ! az network private-endpoint show -g "${NET_RG}" -n "$name" >/dev/null 2>&1; then
    az network private-endpoint create -g "${NET_RG}" -n "$name" -l "${LOCATION}" \
      --vnet-name "${VNET_NAME}" --subnet "${SNET_PE_NAME}" \
      --private-connection-resource-id "$rid" \
      --group-ids "$group" \
      --connection-name "$conn" -o none
  fi
}
create_dzg () {
  local pe="${1-}"; local zone="${2-}"; local dzg="${3-}"
  [[ -z "$pe" || -z "$zone" || -z "$dzg" ]] && { echo "   ! create_dzg: missing args — skip"; return 0; }
  if ! az network private-endpoint dns-zone-group show -g "${NET_RG}" --endpoint-name "$pe" -n "$dzg" >/dev/null 2>&1; then
    az network private-endpoint dns-zone-group create -g "${NET_RG}" --endpoint-name "$pe" \
      -n "$dzg" --private-dns-zone "$zone" -o none
  fi
}

if [[ "${ENABLE_PE_KV}" == "true" ]]; then
  if az keyvault show -g "${KV_RG}" -n "${KV_NAME}" >/dev/null 2>&1; then
    KV_ID="$(az keyvault show -g "${KV_RG}" -n "${KV_NAME}" --query id -o tsv)"
    create_pe  "pe-${KV_NAME}-kv" "$KV_ID" "vault"  "conn-${KV_NAME}-kv"
    create_dzg "pe-${KV_NAME}-kv" "${Z_KV}" "dzg-${KV_NAME}-kv"
  else
    echo "   ! KV ${KV_RG}/${KV_NAME} not found; skipping KV PE."
  fi
fi

if [[ "${ENABLE_PE_ACR}" == "true" ]]; then
  if az acr show -g "${ACR_RG}" -n "${ACR_NAME}" >/dev/null 2>&1; then
    ACR_ID="$(az acr show -g "${ACR_RG}" -n "${ACR_NAME}" --query id -o tsv)"
    create_pe  "pe-${ACR_NAME}-acr" "$ACR_ID" "registry" "conn-${ACR_NAME}-acr"
    create_dzg "pe-${ACR_NAME}-acr" "${Z_ACR}" "dzg-${ACR_NAME}-acr"
  else
    echo "   ! ACR ${ACR_RG}/${ACR_NAME} not found; skipping ACR PE."
  fi
fi

echo "✓ Core networking ensured:"
echo "  RG='${NET_RG}', VNet='${VNET_NAME}'"
echo "  Subnets:"
echo "    - ${SNET_WORKLOADS_NAME}: ${REQ_W_CIDR}"
echo "    - ${SNET_PE_NAME}:       ${REQ_PE_CIDR} (PE policies Disabled)"
echo "  Private DNS zones linked: ${Z_BLOB}, ${Z_DFS}, ${Z_KV}, ${Z_ACR}"
