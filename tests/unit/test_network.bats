#!/usr/bin/env bats

# Unit tests for core_network.sh

setup() {
  export NET_RG="rg-test-network"
  export VNET_NAME="vnet-test-core"
  export VNET_CIDR="10.10.0.0/16"
  export SNET_WORKLOADS_NAME="snet-workloads"
  export SNET_WORKLOADS_CIDR="10.10.0.0/24"
  export SNET_PE_NAME="snet-private-endpoints"
  export SNET_PE_CIDR="10.10.1.0/24"
  export LOCATION="eastus"
}

@test "core_network.sh has correct shebang" {
  head -n1 scripts/core_network.sh | grep -q "#!/usr/bin/env bash"
}

@test "core_network.sh uses set -euo pipefail" {
  grep -q "set -euo pipefail" scripts/core_network.sh
}

@test "core_network.sh validates required variables" {
  grep -q "validate_required_vars" scripts/core_network.sh
}

@test "core_network.sh has Python CIDR calculation" {
  grep -q "python3" scripts/core_network.sh
  grep -q "ipaddress" scripts/core_network.sh
}

@test "core_network.sh creates VNet idempotently" {
  grep -q "az network vnet show" scripts/core_network.sh
  grep -q "az network vnet create" scripts/core_network.sh
}

@test "core_network.sh creates subnets" {
  grep -q "az network vnet subnet create" scripts/core_network.sh
}

@test "core_network.sh creates private DNS zones" {
  grep -q "az network private-dns zone" scripts/core_network.sh
}

@test "core_network.sh creates VNet links" {
  grep -q "az network private-dns link vnet" scripts/core_network.sh
}

@test "core_network.sh disables private endpoint policies" {
  grep -q "private-endpoint-network-policies" scripts/core_network.sh
}
