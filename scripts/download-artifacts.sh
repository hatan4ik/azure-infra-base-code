#!/usr/bin/env bash
# One-time setup
#az extension add --name azure-devops
#az devops configure --defaults organization=https://dev.azure.com/ExampleCorpOps project=ExampleCorp

# Find the most recent run of the pipeline
PIPE_ID=$(az pipelines list --query "[?name=='02-vnet-dns-pe-setup'].id | [0]" -o tsv)
RUN_ID=$(az pipelines runs list --pipeline-ids $PIPE_ID --top 1 --query "[0].id" -o tsv)

# Download the artifact to the current directory
az pipelines runs artifact download \
  --run-id $RUN_ID \
  --artifact-name network-outputs \
  --path ./out
# The files will be in a directory named after the artifact
ls -la ./network-outputs
