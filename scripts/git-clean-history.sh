#!/usr/bin/env bash
set -euo pipefail

# git-clean-history.sh
# Cleans Git history by creating a fresh orphan branch
# WARNING: This is destructive and cannot be undone

echo "=========================================="
echo "Git History Cleanup Script"
echo "=========================================="
echo ""
echo "WARNING: This will:"
echo "  - Remove all Git history"
echo "  - Create a fresh initial commit"
echo "  - Force push to origin/main"
echo ""
echo "This action CANNOT be undone!"
echo ""

# Confirmation
read -p "Type 'YES' to proceed: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Step 1: Creating orphan branch..."
git checkout --orphan clean-main

echo "Step 2: Staging all files..."
git add -A

echo "Step 3: Creating initial commit..."
git commit -m "Initial public snapshot"

echo "Step 4: Renaming branch to main..."
git branch -M main

echo "Step 5: Cleaning up reflog and garbage collection..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo ""
echo "Step 6: Force pushing to origin/main..."
read -p "Ready to force push? Type 'PUSH' to continue: " PUSH_CONFIRM
if [[ "$PUSH_CONFIRM" != "PUSH" ]]; then
  echo "Skipped force push. You can manually push with:"
  echo "  git push --force origin main"
  exit 0
fi

git push --force origin main

echo ""
echo "=========================================="
echo "✓ Git history cleaned successfully"
echo "=========================================="
echo ""
echo "All commits have been squashed into a single initial commit."
echo "The repository history has been permanently removed."
