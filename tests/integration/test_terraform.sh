#!/usr/bin/env bash
set -euo pipefail

# Integration tests for Terraform modules

echo "Running Terraform validation tests..."

FAILED=0

test_module() {
  local module=$1
  echo "Testing module: $module"
  
  cd "terraform/modules/$module"
  
  # Validate syntax
  if ! terraform fmt -check -recursive; then
    echo "❌ $module: Format check failed"
    ((FAILED++))
  else
    echo "✓ $module: Format OK"
  fi
  
  # Validate configuration
  if ! terraform init -backend=false >/dev/null 2>&1; then
    echo "❌ $module: Init failed"
    ((FAILED++))
  else
    echo "✓ $module: Init OK"
  fi
  
  if ! terraform validate >/dev/null 2>&1; then
    echo "❌ $module: Validation failed"
    ((FAILED++))
  else
    echo "✓ $module: Validation OK"
  fi
  
  cd - >/dev/null
}

# Test all modules
for module in managed-identity bootstrap network storage powerbi-gateway; do
  test_module "$module"
done

# Test environments
for env in dev stage prod; do
  echo "Testing environment: $env"
  cd "terraform/environments/$env"
  
  if ! terraform fmt -check; then
    echo "❌ $env: Format check failed"
    ((FAILED++))
  else
    echo "✓ $env: Format OK"
  fi
  
  cd - >/dev/null
done

if [[ $FAILED -eq 0 ]]; then
  echo ""
  echo "✓ All Terraform tests passed"
  exit 0
else
  echo ""
  echo "❌ $FAILED test(s) failed"
  exit 1
fi
