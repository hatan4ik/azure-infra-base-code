#!/usr/bin/env bash
set -euo pipefail

SUB_ID="$(az account show --query id -o tsv)"

# TAGS
declare -a TAGS=(
  "BusinessUnit=$(TAG_BusinessUnit:-core)"
  "Environment=$(TAG_Environment:-prod)"
  "Owner=$(TAG_Owner:-platform-team)"
  "System=$(TAG_System:-example-platform)"
  "Project=$(TAG_Project:-example)"
  "Lifecycle=$(TAG_Lifecycle:-long-lived)"
  "Contact=$(TAG_Contact:-devops@example.com)"
)

tag_merge(){ local rid="$1"; shift; az resource tag --ids "$rid" --is-incremental --only-show-errors --tags "$@" >/dev/null; }

# RG
if ! az group show -n "$(NET_RG)" >/dev/null 2>&1; then
  az group create -n "$(NET_RG)" -l "$(LOCATION)" --tags "${TAGS[@]}" -o none
else
  tag_merge "/subscriptions/${SUB_ID}/resourceGroups/$(NET_RG)" "${TAGS[@]}"
fi

# python helpers
py_contains(){ python3 - <<'PY' "$1" "$2"
import sys,ipaddress
sup=ipaddress.ip_network(sys.argv[1]); sub=ipaddress.ip_network(sys.argv[2])
print(str(sub.subnet_of(sup)).lower())
PY
}
py_children(){ python3 - <<'PY' "$1"
import sys,ipaddress
b=ipaddress.ip_network(sys.argv[1])
p=max(b.prefixlen+1,24)
while True:
  kids=list(b.subnets(new_prefix=p))
  if len(kids)>=2 or p>=b.max_prefixlen: break
  p+=1
print(str(kids[0]), str(kids[1]))
PY
}

# VNet
if ! az network vnet show -g "$(NET_RG)" -n "$(VNET_NAME)" >/dev/null 2>&1; then
  az network vnet create -g "$(NET_RG)" -n "$(VNET_NAME)" -l "$(LOCATION)" --address-prefixes "$(VNET_CIDR)" -o none
fi
mapfile -t CUR_SPACES < <(az network vnet show -g "$(NET_RG)" -n "$(VNET_NAME)" --query 'addressSpace.addressPrefixes[]' -o tsv)

fits(){ local s="$1"; for p in "${CUR_SPACES[@]:-}"; do [[ "$(py_contains "$p" "$s")" == "true" ]] && return 0; done; return 1; }
ensure_space(){ local want="$1"; for p in "${CUR_SPACES[@]:-}"; do [[ "$p" == "$want" ]] && return 0; done; az network vnet update -g "$(NET_RG)" -n "$(VNET_NAME)" --address-prefixes "${CUR_SPACES[@]}" "$want" -o none; mapfile -t CUR_SPACES < <(az network vnet show -g "$(NET_RG)" -n "$(VNET_NAME)" --query 'addressSpace.addressPrefixes[]' -o tsv); }

REQ_W="$(SNET_WORKLOADS_CIDR)"
REQ_PE="$(SNET_PE_CIDR)"
if ! fits "$REQ_W" || ! fits "$REQ_PE"; then ensure_space "$(VNET_CIDR)"; fi
if ! fits "$REQ_W" || ! fits "$REQ_PE"; then
  BASE="${CUR_SPACES[0]}"; read -r NEW_W NEW_PE < <(py_children "$BASE")
  echo "Re-basing subnets inside $BASE: $(SNET_WORKLOADS_NAME)=$NEW_W $(SNET_PE_NAME)=$NEW_PE"
  REQ_W="$NEW_W"; REQ_PE="$NEW_PE"
fi

# Subnets
if ! az network vnet subnet show -g "$(NET_RG)" --vnet-name "$(VNET_NAME)" -n "$(SNET_WORKLOADS_NAME)" >/dev/null 2>&1; then
  az network vnet subnet create -g "$(NET_RG)" --vnet-name "$(VNET_NAME)" -n "$(SNET_WORKLOADS_NAME)" --address-prefixes "$REQ_W" -o none
else
  az network vnet subnet update -g "$(NET_RG)" --vnet-name "$(VNET_NAME)" -n "$(SNET_WORKLOADS_NAME)" --address-prefixes "$REQ_W" -o none || true
fi
if ! az network vnet subnet show -g "$(NET_RG)" --vnet-name "$(VNET_NAME)" -n "$(SNET_PE_NAME)" >/dev/null 2>&1; then
  az network vnet subnet create -g "$(NET_RG)" --vnet-name "$(VNET_NAME)" -n "$(SNET_PE_NAME)" --address-prefixes "$REQ_PE" --private-endpoint-network-policies Disabled -o none
else
  az network vnet subnet update -g "$(NET_RG)" --vnet-name "$(VNET_NAME)" -n "$(SNET_PE_NAME)" --address-prefixes "$REQ_PE" --private-endpoint-network-policies Disabled -o none || true
fi

VNET_ID="$(az network vnet show -g "$(NET_RG)" -n "$(VNET_NAME)" --query id -o tsv)"

# Private DNS + links
for zone in "$(Z_BLOB)" "$(Z_DFS)" "$(Z_KV)" "$(Z_ACR)"; do
  [[ -z "$zone" || "$zone" == "null" ]] && continue
  az network private-dns zone show -g "$(NET_RG)" -n "$zone" >/dev/null 2>&1 || az network private-dns zone create -g "$(NET_RG)" -n "$zone" -o none
  link="ln-$(VNET_NAME)-${zone//./-}"
  az network private-dns link vnet show -g "$(NET_RG)" -z "$zone" -n "$link" >/dev/null 2>&1 || \
  az network private-dns link vnet create -g "$(NET_RG)" -z "$zone" -n "$link" -v "$VNET_ID" -e false -o none
done

echo "✓ Core network ensured: VNet $(VNET_NAME) in RG $(NET_RG)"
