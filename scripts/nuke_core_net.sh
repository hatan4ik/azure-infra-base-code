#!/usr/bin/env bash
set -euo pipefail
# DANGER: deletes the core network RG
if az group show -n "${NET_RG}" >/dev/null 2>&1; then
  az group delete -n "${NET_RG}" --yes --no-wait
  echo "Delete requested for RG ${NET_RG}."
else
  echo "RG ${NET_RG} not found; nothing to delete."
fi
