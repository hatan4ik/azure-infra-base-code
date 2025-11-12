# Pipelines (Azure DevOps)

- `azure-pipelines.yml` → per‑environment pipeline (Lint → Plan → Apply).
- `azure-pipelines-promotion.yml` → Dev → Stage → Prod promotion (requires Environments).
- Templates:
  - `steps-lint.yml`: install Terraform, TFLint, Checkov; fmt/validate/tlint/check.
  - `steps-terraform.yml`: init/plan/apply with ARM OIDC and remote state.
  - `steps-acr-sign.yml`: optional cosign signing step for container images.

## Secrets
- Store cosign materials in Key Vault (`COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD`) and fetch with `AzureKeyVault@2` before signing stage.
