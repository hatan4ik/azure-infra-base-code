#!/usr/bin/env bash
set -euo pipefail

# validate-config.sh
# Validates configuration and checks for placeholder values

echo "=========================================="
echo "Configuration Validation"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

check_placeholder() {
  local file=$1
  local pattern=$2
  local description=$3
  
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "⚠️  WARNING: $description"
    echo "   File: $file"
    echo "   Pattern: $pattern"
    ((WARNINGS++))
  fi
}

check_required_value() {
  local var_name=$1
  local var_value=${!var_name:-}
  
  if [[ -z "$var_value" ]]; then
    echo "❌ ERROR: $var_name is not set"
    ((ERRORS++))
  elif [[ "$var_value" == *"example"* ]] || [[ "$var_value" == *"Example"* ]]; then
    echo "⚠️  WARNING: $var_name contains 'example': $var_value"
    ((WARNINGS++))
  fi
}

echo "Checking for placeholder values..."
echo ""

# Check README
check_placeholder "README.md" "YourOrg" "Replace 'YourOrg' with your Azure DevOps organization"
check_placeholder "README.md" "YourProject" "Replace 'YourProject' with your Azure DevOps project"
check_placeholder "README.md" "<your-subscription-id>" "Replace subscription ID placeholder"
check_placeholder "README.md" "<your-tenant-id>" "Replace tenant ID placeholder"

# Check pipelines
check_placeholder "pipelines/azure-pipelines.yaml" "ExampleCorp" "Replace 'ExampleCorp' organization name"
check_placeholder "pipelines/azure-pipelines.yaml" "00000000-0000-0000-0000-000000000000" "Replace dummy Power BI environment ID"
check_placeholder "pipelines/00-zero-to-hero.yaml" "ExampleCorpOps" "Replace organization name in zero-to-hero"

# Check Terraform
if [[ -f "terraform/environments/dev/terraform.tfvars" ]]; then
  check_placeholder "terraform/environments/dev/terraform.tfvars" "00000000-0000-0000-0000-000000000000" "Replace dummy GUIDs in terraform.tfvars"
fi

echo ""
echo "Checking resource naming conventions..."
echo ""

# Check for 'example' in resource names
check_placeholder "pipelines/03-var-groups-kve.yaml" "rg-example-" "Resource groups use 'example' prefix"
check_placeholder "pipelines/03-var-groups-kve.yaml" "stexample" "Storage accounts use 'example' prefix"
check_placeholder "pipelines/03-var-groups-kve.yaml" "kv-example-" "Key Vaults use 'example' prefix"

echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [[ $ERRORS -gt 0 ]]; then
  echo "❌ Configuration has errors. Please fix before deploying."
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo "⚠️  Configuration has warnings. Review placeholders before deploying."
  echo ""
  echo "Run: ./scripts/replace-placeholders.sh to fix automatically"
  exit 0
else
  echo "✓ Configuration validated successfully"
  exit 0
fi
