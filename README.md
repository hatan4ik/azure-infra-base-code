# Example Cloud Infrastructure Platform

ExampleCorp’s Infrastructure Platform repository is the single source of truth for provisioning, securing, and operating the company’s Azure landing zones. The Engineering Board (Azure Architecture, DevOps, Entra ID Security, Automation Engineering) owns the blueprint and enforces three non‑negotiable pillars:

- **Security First** – passwordless automation via OIDC, least‑privilege RBAC, auditable declarations.
- **Complete Automation** – no manual steps from bootstrap to teardown; everything is pipelined or scripted.
- **Robustness & Resilience** – idempotent scripts, defensive retries, observability, and safe rollback paths.

This document captures the current architecture, the intended business outcomes, and a curated set of improvements to keep the platform aligned with these pillars.

---

## 1. Architecture & Flow

**Business Problem**  
The platform must let multiple product lines deploy shared Azure foundation services (state RGs, VNets, Key Vault, ACR, customer ADLS, and analytical connectivity) in a repeatable, governed manner without leaking credentials or requiring portal clicks.

**High-Level Flow**
1. **Configuration Spine** – Azure DevOps Variable Groups + pipeline variables hold environment metadata, CIDRs, and feature toggles.
2. **Orchestrator Pipeline** – `pipelines/azure-pipelines.yaml` sequences optional variable-group seeding, bootstrap, core network, customer storage, and Power BI gateway stages. Each stage receives the OIDC service connection and points to the shared `scripts/` directory.
3. **Implementation Scripts** – Bash utilities under `scripts/` perform the actual Azure CLI work: creating RGs, tagging assets, enabling diagnostics, wiring RBAC, managing private endpoints, and provisioning the Microsoft.PowerPlatform VNet gateway.
4. **Terraform Environments** – `environments/{dev,stage,prod}` reference versioned modules for teams that still need Terraform-based provisioning; pipelines/templates provide consistent init/plan/apply behavior.
5. **Runbooks & Docs** – `Platform_Documentation.md`, `WIKI/`, and `review.md` outline the governance model, troubleshooting paths, and historical decisions.

**Key Design Choices**
- **Pipelines orchestrate; scripts implement.** YAML files remain declarative and forward parameters to hardened Bash scripts.
- **Workload Identity Federation everywhere.** A user-assigned managed identity (`ado-wif-mi`) plus federated credential powers every Azure CLI invocation, eliminating secrets.
- **Idempotent resource handlers.** Each script checks for existing resources, merges tags, and replays diagnostic settings to ensure safe re-runs.
- **Optional analytics connectivity.** The Power BI VNet gateway stage lets the data platform consume storage accounts that are locked behind private endpoints without punching public holes.

---

## 2. Repository Map

| Path | Purpose |
|------|---------|
| `pipelines/azure-pipelines.yaml` | Primary orchestrator (stages 00–04 + teardown). |
| `pipelines/stages/*.stage.yml` | Stage templates for variable groups, bootstrap, core networking, customer storage, Power BI gateway, and nuke operations. |
| `pipelines/03-var-groups-kve.yaml` | Idempotently builds classic + Key Vault-backed variable groups through the ADO REST API. |
| `pipelines/90-nuke-core-net.yaml` | Controlled teardown of the core networking stack with lock/PE cleanup. |
| `pipelines/templates/` | Shared job/step snippets (terraform, lint, OIDC sanity, variable attachment). |
| `pipelines/steps/prepare-scripts.step.yml` | Normalises line endings/executables before script execution on hosted agents. |
| `scripts/*.sh` | Implementation scripts for bootstrap, networking, storage, OIDC setup/cleanup, validations, and the Power BI VNet gateway (default API version `2020-10-30-preview`). |
| `scripts/list-powerbi-environments.sh` | Helper that prints Power Platform environment resource IDs; accepts optional region filter. |
| `environments/<env>/` | Terraform entry points targeting remote modules (`example.*`) with shared state backend settings. |
| `WIKI/`, `Platform_Documentation.md`, `review.md` | Knowledge base of architecture context, board assessments, and prioritized remediation items. |
| `archive/` | Legacy monolithic pipelines retained for historical reference only. |

---

## 3. Security & Compliance Posture

- **Authentication:** Only OIDC-based service connections are permitted. Managed identities receive scoped roles (`Contributor`, `Key Vault Secrets User`, `Storage Blob Data Contributor`, `AcrPull`).
- **Secrets Handling:** Variable groups never store secrets; sensitive values flow through Key Vault-backed VGs or Azure AD endpoints.
- **Networking:** Core VNet scripts enforce private endpoints, DNS zones, and optional delegated subnets for analytics gateways.
- **Observability:** Bootstrap scripts attach diagnostics to Key Vault, storage, and ACR resources, streaming to Log Analytics.
- **Access Reviews:** Role assignment helpers check for existing grants before creating new ones to reduce over-provisioning.

---

## 4. Getting Started

1. **Tooling:** Install Azure CLI ≥2.50, `jq`, `python3`, and ensure you can grant the UAMI RBAC roles required by automation.
2. **OIDC Setup:** Follow `scripts/README.md` to create the federated service connection (`create-oidc-connection-from-mi.sh` + federated credential command).
3. **Configuration:** Run `pipelines/03-var-groups-kve.yaml` (System.AccessToken enabled) to seed `vg-core-bootstrap`, `vg-core-network`, `vg-customer-<slug>`, Key Vault-backed VGs, and optional `vg-powerbi-gateway`.
4. **Deployment:** Execute `pipelines/azure-pipelines.yaml`. Set `RUN_VARS_SETUP=true` when you need to rehydrate variable groups. Provide Power BI variables (`ENABLE_PBI_GATEWAY`, `PBI_*`, `PBI_DELEGATION`, plus either `PBI_ENVIRONMENT_IDS` or `PBI_ENVIRONMENT_LINKS` pasted from the admin portal) via pipeline variables or a VG.
5. **Validation:** Use `pipelines/templates/oidc-sanity.yaml` in any pipeline to confirm service connection health, and `pipelines/sanity-check.yaml` for smoke tests.

---

## 5. Operations & Runbooks

- **Bootstrap:** `scripts/bootstrap.sh` creates RGs, storage, Key Vault (RBAC mode, purge protection), Log Analytics, ACR, and RBAC bindings for the managed identity.
- **Core Network:** `scripts/vnet_dns_pe.sh` ensures VNets, subnets, DNS zones, optional platform private endpoints, and — if enabled — the subnet delegation for the Power BI gateway.
- **Customer Storage:** `scripts/customer_storage.sh` provisions ADLS Gen2 accounts per customer, with containers, diagnostics, RBAC, and optional private endpoints into the core VNet.
- **Power BI Gateway:** `scripts/powerbi_gateway.sh` registers Microsoft.PowerPlatform, validates subnet delegation (`PBI_DELEGATION`, default `Microsoft.PowerPlatform/vnetaccesslinks`), and upserts the `vnetGateways` resource plus environment associations (builds IDs automatically when `PBI_ENVIRONMENT_LINKS` are provided). Default API version is `2020-10-30-preview`; override `PBI_GATEWAY_API_VERSION` if Microsoft exposes a newer version in your tenant.
- **Teardown:** `pipelines/90-nuke-core-net.yaml` removes private endpoints, locks, and the networking RG (with dry-run and confirmation gates).
- **Utilities:** `scripts/devops-pull-repos.sh`, `download-artifacts.sh`, `list-powerbi-environments.sh`, `check-powerbi-gateway.sh`, and `cleanup-oidc-mi-connection.sh` support developer onboarding and hygiene.
- **Power BI execution helper:** `scripts/run-powerbi-gateway.sh` invokes the gateway provisioning script with repo defaults for quick local runs.

---

## Power BI VNet Integration (End-to-End Story)

1. **Lock storage behind private endpoints**  
   `scripts/customer_storage.sh` creates ADLS Gen2 accounts, containers, diagnostics, and Private Endpoints + DNS zone groups so storage is reachable only from the core VNet.

2. **Prepare the gateway subnet**  
   Enable `ENABLE_PBI_GATEWAY=true` (plus `PBI_SUBNET_NAME/CIDR`) before running Stage 02. `scripts/vnet_dns_pe.sh` ensures the subnet exists and delegates it to `PBI_DELEGATION` (default `Microsoft.PowerPlatform/vnetaccesslinks`), allowing Microsoft to host managed gateway instances inside your VNet.

3. **Provision the Microsoft-managed VNet gateway**  
   Stage 04 calls `scripts/powerbi_gateway.sh`, which:
   - Registers `Microsoft.PowerPlatform` (using `PBI_GATEWAY_API_VERSION`, default `2020-10-30-preview` per current tenant support).
   - Validates the delegated subnet and creates/updates the `Microsoft.PowerPlatform/vnetGateways/<name>` resource.
   - Associates one or more Power Platform environments (supply `PBI_ENVIRONMENT_IDS` directly or drop admin-center URLs into `PBI_ENVIRONMENT_LINKS` and the script converts them).

4. **Configure Power BI workspaces**  
   In `app.powerbi.com`, go to the workspace bound to those environments and choose the VNet data gateway for your datasets. Power BI’s SaaS control plane now routes refreshes through the managed gateway sitting inside your VNet, which then reaches the storage accounts via private endpoints.

5. **RBAC & observability**  
   Grant the Power BI managed identity/service principal the necessary RBAC (e.g., `Storage Blob Data Reader`) on each storage account. Use Activity Log alerts or diagnostics to watch for gateway/subnet changes and keep the automation variables (`PBI_*`) under source control.

Result: Power BI accesses Azure Storage without any public exposure—traffic flows SaaS → managed gateway (delegated subnet) → storage private endpoint.

---

## 6. Engineering Guardrails

- **Idempotent scripts**: Existence checks, incremental tag merges, repeatable diagnostics.
- **Strict Bash discipline**: `set -euo pipefail`, minimal inline YAML logic, command guarding (`command -v jq || apt-get install`).
- **Observability & logging**: Clear echo statements for each action, Log Analytics wiring, optional tree listings for debugging.
- **Safe defaults**: Public network access disabled where possible, purge protection enforced, TLS 1.2 minimum, container soft-delete.

---

## 7. Improvement Backlog

1. **Unify Script Naming & Location** – Remove legacy duplicates (`bootstrap.sh` vs `boostrap.sh`, `core-net.sh` vs `core_network.sh`) and archive unused variants to prevent drift.
2. **Template Modernisation** – Convert remaining multi-stage templates to job templates and consolidate parameter handling (e.g., `pipelines/templates/stage-0*.yml`).
3. **Automated Testing** – Introduce script-level unit tests (e.g., `bats` or Python harness) and add lint jobs (`shellcheck`, `shfmt`) to the pipelines/templates directory.
4. **Configuration Registry** – Replace ad-hoc variable groups with a structured configuration file (YAML/JSON) validated via JSON Schema to reduce manual VG edits.
5. **Power BI Gateway Readiness Probe** – Extend `powerbi_gateway.sh` with Azure Resource Graph or REST polling to verify the gateway reaches `Succeeded` before exiting.
6. **Terraform Pipeline Alignment** – Update `pipelines/templates/steps-terraform.yml` to use the same OIDC connection and add plan artifact publishing for policy reviews.
7. **Documentation Consolidation** – Fold redundant wiki pages into `Platform_Documentation.md` and cross-link to the new architecture overview for a single onboarding narrative.
8. **Cost & FinOps Hooks** – Integrate tagging compliance checks and optional budget alerts (e.g., via Policy or `az consumption`) to align with `WIKI/06_FinOps.md`.

Track these as Engineering Board work items to progressively mature the platform.

---

## 8. Further Reading

- `scripts/README.md` – Complete OIDC/service-connection guide.
- `Platform_Documentation.md` – Deep component breakdown, including stage-by-stage commentary.
- `WIKI/*.md` – Architecture, getting started, pipelines, security, FinOps, troubleshooting.
- `review.md` – Latest board assessment with detailed findings and rationale.

Welcome aboard. Uphold the standards, automate everything, and keep the platform secure.
