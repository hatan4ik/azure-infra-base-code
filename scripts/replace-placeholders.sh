#!/usr/bin/env bash
set -euo pipefail

# replace-placeholders.sh
# Interactive script to replace placeholder values

echo "=========================================="
echo "Placeholder Replacement Wizard"
echo "=========================================="
echo ""
echo "This script will help you replace placeholder values"
echo "with your actual configuration."
echo ""

# Collect values
read -p "Azure DevOps Organization (e.g., MyCompany): " ADO_ORG
read -p "Azure DevOps Project (e.g., MyProject): " ADO_PROJECT
read -p "Azure Subscription ID: " SUBSCRIPTION_ID
read -p "Azure Tenant ID: " TENANT_ID
read -p "Company/Project prefix (e.g., mycompany): " PREFIX

echo ""
echo "You entered:"
echo "  Organization: $ADO_ORG"
echo "  Project: $ADO_PROJECT"
echo "  Subscription: $SUBSCRIPTION_ID"
echo "  Tenant: $TENANT_ID"
echo "  Prefix: $PREFIX"
echo ""
read -p "Proceed with replacement? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Replacing placeholders..."

# Backup files
BACKUP_DIR=".placeholder-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "Creating backups in $BACKUP_DIR/"

# Function to replace in file
replace_in_file() {
  local file=$1
  local old=$2
  local new=$3
  
  if [[ -f "$file" ]]; then
    cp "$file" "$BACKUP_DIR/$(basename "$file")"
    sed -i.tmp "s|$old|$new|g" "$file" && rm -f "$file.tmp"
    echo "  ✓ Updated: $file"
  fi
}

# Replace in README
replace_in_file "README.md" "YourOrg" "$ADO_ORG"
replace_in_file "README.md" "YourProject" "$ADO_PROJECT"
replace_in_file "README.md" "<your-subscription-id>" "$SUBSCRIPTION_ID"
replace_in_file "README.md" "<your-tenant-id>" "$TENANT_ID"

# Replace in pipelines
replace_in_file "pipelines/azure-pipelines.yaml" "ExampleCorp" "$ADO_PROJECT"
replace_in_file "pipelines/00-zero-to-hero.yaml" "ExampleCorpOps" "$ADO_ORG"
replace_in_file "pipelines/00-zero-to-hero.yaml" "ExampleCorp" "$ADO_PROJECT"

# Replace resource naming
replace_in_file "pipelines/03-var-groups-kve.yaml" "example" "$PREFIX"
replace_in_file "pipelines/azure-pipelines.yaml" "example" "$PREFIX"

# Replace in Terraform
if [[ -f "terraform/environments/dev/terraform.tfvars.example" ]]; then
  cp "terraform/environments/dev/terraform.tfvars.example" "terraform/environments/dev/terraform.tfvars"
  replace_in_file "terraform/environments/dev/terraform.tfvars" "00000000-0000-0000-0000-000000000000" "$SUBSCRIPTION_ID"
  replace_in_file "terraform/environments/dev/terraform.tfvars" "ExampleCorpOps" "$ADO_ORG"
  replace_in_file "terraform/environments/dev/terraform.tfvars" "ExampleCorp" "$ADO_PROJECT"
fi

echo ""
echo "=========================================="
echo "✓ Placeholder replacement complete"
echo "=========================================="
echo ""
echo "Backups saved to: $BACKUP_DIR/"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Update Power BI environment IDs if needed"
echo "  3. Run: ./scripts/validate-config.sh"
echo "  4. Deploy: az pipelines run --name 00-zero-to-hero"
