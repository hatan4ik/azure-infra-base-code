#!/bin/bash

# --- Configuration ---
# Replace with your Azure DevOps organization URL and project name.
ORGANIZATION_URL="https://dev.azure.com/ExampleCorpOps/"
PROJECT_NAME="ExampleCorp"
# --- End Configuration ---

# Set default organization and project for subsequent commands
az devops configure --defaults organization="$ORGANIZATION_URL" project="$PROJECT_NAME"

echo "Fetching repositories from project '$PROJECT_NAME'..."

# Get repository clone URLs. Using SSH URLs is recommended for developers.
# Ensure you have SSH keys configured with Azure DevOps.
# If you prefer HTTPS, change 'sshUrl' to 'webUrl'.
# The 'jq' tool is used here to parse the JSON output. Use 'webUrl' for HTTPS.
REPO_URLS=$(az repos list --query "[].webUrl" -o json | jq -r '.[]')

if [ -z "$REPO_URLS" ]; then
  echo "No repositories found or you may not have permission to list them."
  echo "Please check your organization, project name, and permissions."
  exit 1
fi

echo "Found repositories. Starting clone process..."
echo "=============================================="

for url in $REPO_URLS; do
  # Extract the repository name from the URL to use as the folder name
  repo_name=$(basename "$url" .git)

  if [ -d "$repo_name" ]; then
    echo "Directory '$repo_name' already exists. Skipping clone."
  else
    echo "Cloning '$repo_name'..."
    git clone "$url"
  fi
  echo "----------------------------------------------"
done

echo "=============================================="
echo "All repositories have been processed."
