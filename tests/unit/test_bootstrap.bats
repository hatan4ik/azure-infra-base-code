#!/usr/bin/env bats

# Unit tests for bootstrap.sh

setup() {
  export STATE_RG="rg-test-tfstate"
  export STATE_SA="sttesttfstate"
  export STATE_CONTAINER="tfstate"
  export KV_NAME="kv-test-platform"
  export LAW_NAME="law-test-platform"
  export ACR_NAME="acrtestplatform"
  export LOCATION="eastus"
  export MI_RESOURCE_GROUP="rg-test-wif"
  export MI_NAME="test-wif-mi"
}

@test "bootstrap.sh has correct shebang" {
  head -n1 scripts/bootstrap.sh | grep -q "#!/usr/bin/env bash"
}

@test "bootstrap.sh uses set -euo pipefail" {
  grep -q "set -euo pipefail" scripts/bootstrap.sh
}

@test "bootstrap.sh validates required variables" {
  grep -q "validate_required_vars" scripts/bootstrap.sh
}

@test "bootstrap.sh has input validation function" {
  grep -q "validate_required_vars()" scripts/bootstrap.sh
}

@test "bootstrap.sh checks for required commands" {
  grep -q "command -v" scripts/bootstrap.sh
}

@test "bootstrap.sh has tag merge function" {
  grep -q "tag_merge" scripts/bootstrap.sh
}

@test "bootstrap.sh creates resource group idempotently" {
  grep -q "az group show" scripts/bootstrap.sh
  grep -q "az group create" scripts/bootstrap.sh
}

@test "bootstrap.sh enables Key Vault purge protection" {
  grep -q "enable-purge-protection" scripts/bootstrap.sh
}

@test "bootstrap.sh configures diagnostic settings" {
  grep -q "monitor diagnostic-settings" scripts/bootstrap.sh
}

@test "bootstrap.sh assigns RBAC roles" {
  grep -q "role assignment" scripts/bootstrap.sh
}
