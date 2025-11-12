# Getting Started

1. Create Git repos for each module `example.*` and the consumer repo `example.infra.live`.
2. In `example.infra.live/environments/*/main.tf`, update each module `source` URL to your repos and pinned tags.
3. Configure Azure DevOps:
   - Service connection (ARM OIDC) named `My-ARM-Connection-OIDC`.
   - Library/Variable Group for non‑secrets (`TFSTATE_*`) or keep in `pipelines/vars`.
4. Create pipeline from `example.infra.live/azure-pipelines.yml`. Use Environments with approval on `prod`.
5. Run `dev` → validate, then promote with `azure-pipelines-promotion.yml`.
