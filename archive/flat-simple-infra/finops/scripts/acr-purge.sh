#!/usr/bin/env bash
set -euo pipefail
ACR_NAME=${1:?Usage: $0 <acr_name> [ago, default 30d]}
AGO=${2:-30d}
az acr run -n "$ACR_NAME" --cmd "acr purge --filter '*/.*' --untagged --ago $AGO" /dev/null
