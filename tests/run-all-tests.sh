#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "Running All Tests"
echo "=========================================="
echo ""

FAILED=0

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v bats >/dev/null 2>&1; then
  echo "❌ Bats not installed. Install with: brew install bats-core"
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "⚠️  Terraform not installed. Skipping Terraform tests."
  SKIP_TF=true
else
  SKIP_TF=false
fi

echo "✓ Prerequisites OK"
echo ""

# Run unit tests
echo "=========================================="
echo "Running Unit Tests (Bats)"
echo "=========================================="
if ! bats tests/unit/*.bats; then
  echo "❌ Unit tests failed"
  ((FAILED++))
else
  echo "✓ Unit tests passed"
fi
echo ""

# Run Terraform tests
if [[ "$SKIP_TF" == "false" ]]; then
  echo "=========================================="
  echo "Running Terraform Tests"
  echo "=========================================="
  if ! bash tests/integration/test_terraform.sh; then
    echo "❌ Terraform tests failed"
    ((FAILED++))
  else
    echo "✓ Terraform tests passed"
  fi
  echo ""
fi

# Run configuration validation
echo "=========================================="
echo "Running Configuration Validation"
echo "=========================================="
if ! bash scripts/validate-config.sh; then
  echo "⚠️  Configuration has warnings (non-fatal)"
else
  echo "✓ Configuration validated"
fi
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
if [[ $FAILED -eq 0 ]]; then
  echo "✓ All tests passed"
  exit 0
else
  echo "❌ $FAILED test suite(s) failed"
  exit 1
fi
