# Example Cloud Infrastructure Platform — Overview

The Engineering Board chartered this repository to deliver a **secure, low‑touch Azure landing zone** that product teams can rely on for day‑0 provisioning and day‑N operations. The solution converges Terraform modules, Azure DevOps pipelines, and hardened Bash automation under a single governance model.

## Business Objectives

1. **Security First:** eliminate static credentials by standardising on Workload Identity Federation (OIDC) and least-privilege RBAC.
2. **Complete Automation:** remove portal steps during bootstrap, networking, storage, and analytics connectivity.
3. **Resilience:** create idempotent scripts and teardown playbooks so environments can be recreated or retired without manual fixes.

## Architectural Layers

| Layer | Responsibility | Key Artifacts |
|-------|----------------|---------------|
| **Configuration Spine** | Central variables, feature toggles, and secret references. | `pipelines/03-var-groups-kve.yaml`, `vg-*` variable groups, pipeline variables. |
| **Orchestration** | Defines stage order and parameters; no business logic. | `pipelines/azure-pipelines.yaml`, `pipelines/stages/*.stage.yml`. |
| **Implementation Scripts** | Azure CLI automation for bootstrap, network, storage, OIDC, Power BI gateway, cleanup. | `scripts/*.sh` |
| **Terraform Modules** | Reusable IaC for network, KV, ACR, storage, VMSS agents, private link, RBAC, Defender. | `environments/{dev,stage,prod}`, remote `example.*` modules. |
| **Knowledge Base** | Runbooks, deep dives, board reviews. | `Platform_Documentation.md`, `WIKI/*`, `review.md`. |

## Delivery Flow

1. **Seed variable groups** (optional Stage 00) so pipelines share the same environment metadata and Key Vault-backed secrets.
2. **Bootstrap core services** (Stage 01) — state RG, tfstate storage, hardened Key Vault, Log Analytics, ACR, RBAC for the managed identity.
3. **Provision networking** (Stage 02) — VNets, subnets, Private DNS zones, optional shared-service private endpoints, and delegated subnet for the Power BI gateway.
4. **Roll out customer storage** (Stage 03) — ADLS Gen2 accounts, containers, diagnostics, RBAC, optional private endpoints.
5. **Bridge analytics** (Stage 04) — optional Microsoft.PowerPlatform VNet gateway to keep Power BI traffic on private IPs.
6. **Operate & retire** — `pipelines/90-nuke-core-net.yaml` for controlled teardown, `scripts/cleanup-oidc-mi-connection.sh` for service-connection cleanup, `pipelines/templates/oidc-sanity.yaml` for troubleshooting authentication.

## Security Controls

- Workload Identity Federation with a single user-assigned managed identity (`ado-wif-mi`) per tenant.
- RBAC enforced at the smallest necessary scope (resource group, Key Vault, storage account, ACR).
- Key Vault runs in RBAC mode with purge protection, and all storage accounts enforce TLS 1.2, private endpoints, and diagnostic streams to Log Analytics.
- Power BI connectivity is accomplished via a delegated subnet + VNet data gateway, keeping storage accounts non-public.

## Current Improvement Backlog

1. **Script Consolidation:** retire duplicate legacy Bash files and enforce a single implementation per capability.
2. **Automated Testing:** add `shellcheck`, `shfmt`, and `bats`/unit tests to pipelines to catch regressions early.
3. **Config Registry:** move VG seeds into a validated YAML/JSON manifest to reduce manual edits in pipeline variables.
4. **Terraform Alignment:** update terraform templates to use OIDC and publish plan artifacts for policy review.
5. **Power BI Health Checks:** enhance the VNet gateway script with provisioning-state polling and trace logging.
6. **Documentation Merge:** streamline the wiki and README so onboarding requires a single narrative.

## How to Engage

- Start with `scripts/README.md` (OIDC setup) and the updated `README.md` for architecture context.
- Use this overview plus `Platform_Documentation.md` when presenting design reviews or onboarding new engineers.
- Track improvements as Engineering Board work items; every change should reinforce the three pillars: security, automation, resilience.
