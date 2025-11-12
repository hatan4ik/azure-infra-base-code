# Example Infrastructure Platform: Component Documentation

This document provides a detailed breakdown of every pipeline, template, and script in the repository. It is organized by function, from the main orchestrator down to the individual scripts and legacy artifacts.

## Table of Contents
[[_TOC_]]
1.  **The Modern Orchestration Architecture**
    *   `pipelines/azure-pipelines.yaml` (The Orchestrator)
    *   `pipelines/stages/01-bootstrap.stage.yml` (Stage Template)
    *   `pipelines/stages/03-customer-storage.stage.yml` (Stage Template)
    *   `pipelines/templates/oidc-sanity.yaml` (Utility Job Template)
2.  **Core Implementation Scripts**
    *   `pipelines/bootstrap.sh` (and its duplicates)
    *   `pipelines/scripts/provision-core-net.sh`
    *   `pipelines/scripts/core-net.sh`
3.  **Platform Management Pipelines**
    *   `pipelines/03-var-groups-kve.yaml` (Variable Group Management)
    *   `pipelines/90-nuke-core-net.yaml` (Lifecycle/Teardown)

4.  **Developer Utility & Setup Scripts**
    *   `pipelines/download-artifacts.sh`
    *   `scripts/README.md` (Authentication Guide)
    *   `scripts/create_var_groups.sh`
    *   `scripts/devops-pull-repos.sh`
5.  **Legacy & Archived Artifacts**
    *   `pipelines/00-variable-groups.yaml`
    *   `pipelines/01-bootstrap.yaml` & `pipelines/02-vnet-dns-pe.yaml`
    *   `pipelines/03-customers-storage.yaml`
    *   `pipelines/iac-wif-sample.yaml` & `sanity-check.yaml`
    *   `WIKI/` & `flat-simple-infra/`

---

## 1. The Modern Orchestration Architecture

This is the heart of the platform. These files represent the target state of our CI/CD process, emphasizing orchestration over implementation.

### `pipelines/azure-pipelines.yaml`

*   **Type:** Main Orchestrator Pipeline
*   **Purpose:** To define the end-to-end deployment sequence for the entire platform. It does no work itself; it only calls stage templates in the correct order, passing the necessary parameters and variable groups.
*   **Execution:** This is the primary pipeline to be run manually from the Azure DevOps UI.
*   **Inputs:**
    *   **Variables:** `OIDC_SERVICE_CONNECTION`, `RUN_VARS_SETUP` (boolean flag), `scriptsDir`.
*   **Outputs:** A fully provisioned Azure environment.
*   **Board's Assessment:**
    *   **DevOps Specialist:** "This is the blueprint for our modern architecture. Its clarity is its greatest strength. However, it is currently **broken** as it references templates in a `stages//` path with a double slash and uses filenames that do not match the repository's content. It must be corrected to point to the correct templates in `pipelines/stages/`."

### `pipelines/stages/01-bootstrap.stage.yml`

*   **Type:** Stage Template
*   **Purpose:** To define the "Bootstrap" stage of the pipeline. It sets up the deployment job, environment, and variable groups, and then calls the `bootstrap.sh` script to perform the actual work.
*   **Execution:** Called by `azure-pipelines.yaml`. Not intended to be run directly.
*   **Inputs:**
    *   **Parameters:** `environmentName`, `serviceConnection`, `variableGroups`, `scriptsDir`.
*   **Outputs:** Core Azure resources like the state Resource Group, Key Vault, Log Analytics Workspace, and Container Registry.
*   **Board's Assessment:**
    *   **DevOps Specialist:** "This is a perfect example of a modern stage template. It's declarative and reusable. Its only job is to orchestrate the execution of the `bootstrap.sh` script."
    *   **YAML Parsing Error:** "This file currently has a structural flaw. It is defined with a top-level `stages:` block, which makes it a multi-stage template. It must be refactored to be a single-stage template by removing the `stages:` wrapper to be correctly consumed by the main pipeline."

### `pipelines/stages/03-customer-storage.stage.yml`

*   **Type:** Stage Template
*   **Purpose:** To define the "Customer Storage" stage. It orchestrates the execution of the `customer_storage.sh` script to provision ADLS Gen2 storage for a specific customer.
*   **Execution:** Called by `azure-pipelines.yaml`.
*   **Inputs:**
    *   **Parameters:** `environmentName`, `serviceConnection`, `variableGroups`, `scriptsDir`.
*   **Outputs:** An Azure Data Lake Storage account with associated containers, diagnostics, RBAC, and Private Endpoints.
*   **Board's Assessment:**
    *   **DevOps Specialist:** "Like the bootstrap template, this is a well-designed, reusable component that follows our target architecture."
    *   **Current Extension:** Additional variable groups (e.g., `vg-powerbi-gateway`) are now available for downstream stages and do not impact customer storage behaviors.

### `pipelines/stages/04-powerbi-gateway.stage.yml`

*   **Type:** Stage Template
*   **Purpose:** Orchestrates provisioning of the Power BI VNet data gateway by invoking `scripts/powerbi_gateway.sh`. This binds the delegated subnet to Microsoft.PowerPlatform and associates Power Platform environments so Power BI can reach storage accounts through private endpoints.
*   **Execution:** Optional stage in `azure-pipelines.yaml`; runs only when `ENABLE_PBI_GATEWAY` is set to `true` (either via pipeline variables or an existing variable group). It executes as a simple job; add an Environment manually if release approvals are required.
*   **Inputs:**
    *   **Parameters:** `environmentName`, `serviceConnection`, `variableGroups`, `scriptsDir`.
*   **Outputs:** A `Microsoft.PowerPlatform/vnetGateways` resource linked to the core VNet + delegated subnet.
*   **Board's Assessment:**
    *   **Cloud Architect:** "This finally closes the loop for analytics workloads that must remain on the private backbone. By delegating a dedicated subnet and automating the gateway resource, Power BI can consume storage without reopening public endpoints."
    *   **Security Expert:** "Environment association is driven by configuration, and the pipeline enforces provider registration and subnet delegation before creation—exactly the guardrails we expect."

### `pipelines/templates/oidc-sanity.yaml`

*   **Type:** Utility Job Template
*   **Purpose:** To provide a reusable, self-contained job that verifies the Workload Identity Federation (OIDC) connection is working correctly. It fetches a real OIDC token and validates its claims against the service connection's expected values.
*   **Execution:** Can be included in any pipeline to diagnose authentication issues.
*   **Inputs:**
    *   **Parameters:** `scName` (Service Connection Name), `scIdOverride` (optional GUID), `debug` (boolean).
*   **Outputs:** Detailed logs confirming whether the OIDC issuer and subject match. Fails the job if there is a mismatch.
*   **Board's Assessment:**
    *   **Security Expert:** "This is a brilliant piece of engineering. It provides an automated way to build confidence in our most critical security component. It dramatically speeds up troubleshooting of authentication problems, which are often the most difficult to diagnose."

---

## 2. Core Implementation Scripts

These scripts contain the "how." They are the idempotent, robust workers that perform all the actions in Azure.

### `pipelines/bootstrap.sh` (and its duplicates)

*   **Type:** Core Logic Script
*   **Purpose:** To idempotently create and configure all foundational resources: the state Resource Group, Storage Account for Terraform state, a hardened Key Vault, a Log Analytics Workspace, and an Azure Container Registry. It also assigns necessary RBAC roles to the Managed Identity.
*   **Execution:** Called by the `01-bootstrap.stage.yml` template.
*   **Inputs (as Environment Variables):** `STATE_RG`, `LOCATION`, `STATE_SA`, `KV_NAME`, `MI_RG`, `MI_NAME`, and all `TAG_*` variables.
*   **Board's Assessment:**
    *   **Senior Software Engineer:** "This script is well-written and robust. Its use of `if ! az ... show` checks makes it safely re-runnable. However, its **duplication** in `pipelines/bootstrap.sh`, `pipelines/vars/bootstrap.sh`, and `scripts/bootstrap.sh` is a critical flaw that must be resolved immediately. There should be a single version of this file located at `pipelines/scripts/bootstrap.sh`."

### `pipelines/scripts/provision-core-net.sh`

*   **Type:** Core Logic Script
*   **Purpose:** To idempotently create and configure the core network, including the VNet, subnets (`workloads` and `private-endpoints`), and all necessary Private DNS Zones. It contains intelligent logic to re-calculate subnet CIDRs if the requested ranges don't fit in the VNet's address space. It also supports creating a NAT Gateway.
*   **Execution:** Called by a network stage template (e.g., the legacy `02-vnet-dns-pe.yaml`).
*   **Inputs (as Environment Variables):** `NET_RG`, `VNET_NAME`, `VNET_CIDR`, `SNET_WORKLOADS_CIDR`, `Z_BLOB`, etc.
*   **Board's Assessment:**
    *   **Senior Software Engineer:** "This is a highly advanced and resilient script. The Python-based CIDR calculation is a clever solution to a common networking challenge. This script is production-ready."

### `pipelines/scripts/core-net.sh`

*   **Type:** Core Logic Script (Simplified)
*   **Purpose:** A simpler version of `provision-core-net.sh`. It creates the VNet, subnets, and DNS zones but lacks the more advanced NAT Gateway and CIDR re-basing logic.
*   **Board's Assessment:**
    *   **Senior Software Engineer:** "This script is redundant. It is a less capable version of `provision-core-net.sh`. To avoid confusion and ensure we always use the most robust logic, this file should be **archived**."

---

## 3. Platform Management Pipelines

These are standalone, operational pipelines used for managing the platform itself.

### `pipelines/03-var-groups-kve.yaml`

*   **Type:** Idempotent Management Pipeline
*   **Purpose:** To create or update all Azure DevOps Variable Groups required by the platform. This is the single source of truth for pipeline configuration.
*   **Execution:** Run manually whenever variable group definitions need to be synchronized.
*   **Inputs:** Reads variable values directly from its own `variables:` block to seed the creation process.
*   **Outputs:** Creates/updates `vg-core-bootstrap`, `vg-core-network`, `vg-customer-washington`, and the Key Vault-backed `vg-kv-backend`.
*   **Board's Assessment:**
    *   **Senior Software Engineer:** "This is the most sophisticated piece of automation in the repository. The `upsert_classic` and `upsert_kv` functions, which query the ADO REST API before deciding to `POST` or `PUT`, are a masterclass in idempotency. The use of `jq` to safely construct JSON payloads is a best practice. This pipeline should be the only way variable groups are managed."

### `pipelines/90-nuke-core-net.yaml`

*   **Type:** Lifecycle/Teardown Pipeline
*   **Purpose:** To safely and completely destroy the core network and its dependencies. This is critical for managing non-production environments.
*   **Execution:** Run manually with extreme caution.
*   **Inputs:**
    *   **Variables:** `CONFIRM_NUKE` must be set to `YES` to proceed. `DRY_RUN` can be set to `true` to preview actions.
*   **Outputs:** Deletes Private Endpoints, resource locks, and the core network resource group.
*   **Board's Assessment:**
    *   **Cloud Architect:** "The existence of this script is a mark of a mature and professional operation. It correctly handles dependencies (like PEs in other RGs) and includes safety switches. This is an essential tool for cost management and clean-up."

---

## 4. Developer Utility & Setup Scripts

These files support the development and operational lifecycle.

### `pipelines/download-artifacts.sh`

*   **Type:** Local Utility Script
*   **Purpose:** Allows a developer to easily download the `network-outputs` artifact from the latest successful pipeline run.
*   **Execution:** Run locally from a developer's machine.

### `scripts/README.md`

*   **Type:** Critical Documentation
*   **Purpose:** Provides the definitive, step-by-step guide for setting up the secure, secret-less OIDC service connection.
*   **Board's Assessment:**
    *   **Security Expert:** "This is the most important document for any new engineer. It doesn't just give commands; it explains *why* we use Workload Identity Federation. This document should be moved to the root of the repository to be the main `README.md`."

### `scripts/create_var_groups.sh`

*   **Type:** Setup Script
*   **Purpose:** An idempotent script to create or update a predefined set of variable groups using the ADO REST API.
*   **Execution:** Called by the `00-var-groups.stage.yml` template.
*   **Board's Assessment:**
    *   **Senior Software Engineer:** "This script is functional but less capable than the logic inside `03-var-groups-kve.yaml`. It doesn't handle Key Vault-backed groups and has a simpler payload construction. It should be **archived** in favor of the `03-var-groups-kve.yaml` pipeline."

### `scripts/devops-pull-repos.sh`

*   **Type:** Local Utility Script
*   **Purpose:** A helper script for developers to clone all repositories from the configured Azure DevOps project.
*   **Execution:** Run locally to set up a development environment.

---

## 5. Legacy & Archived Artifacts

These files represent past iterations. They should be considered **read-only** and are candidates for deletion to complete the repository's refactoring.

### `pipelines/00-variable-groups.yaml`

*   **Type:** Legacy Management Pipeline
*   **Purpose:** An early version of the variable group management pipeline. It uses a large inline script and is less capable than its successor.
*   **Verdict:** **ARCHIVE**. Superseded by `03-var-groups-kve.yaml`.

### `pipelines/01-bootstrap.yaml` & `pipelines/02-vnet-dns-pe.yaml`

*   **Type:** Legacy Monolithic Pipelines
*   **Purpose:** These were the original, self-contained pipelines for bootstrapping and network creation. They contain large, hard-to-maintain inline scripts and have been refactored into the modern template-and-script architecture.
*   **Verdict:** **ARCHIVE**. Their logic has been externalized into `.sh` files and their orchestration role is now handled by `azure-pipelines.yaml` and the stage templates.

### `pipelines/03-customers-storage.yaml`

*   **Type:** Legacy Job Template
*   **Purpose:** An early version of the customer storage deployment. It uses a large inline script.
*   **Verdict:** **ARCHIVE**. Superseded by the modern `pipelines/stages/03-customer-storage.stage.yml`.

### `pipelines/iac-wif-sample.yaml` & `sanity-check.yaml`

*   **Type:** Legacy Example Pipelines
*   **Purpose:** These were initial drafts and examples for testing the OIDC connection.
*   **Verdict:** **ARCHIVE**. Their functionality is now provided by the superior and reusable `pipelines/templates/oidc-sanity.yaml` template.

### `WIKI/` & `flat-simple-infra/`

*   **Type:** Obsolete Documentation & Code
*   **Purpose:** These directories contain outdated documentation and an abandoned Terraform implementation.
*   **Verdict:** **ARCHIVE IMMEDIATELY**. This content is actively harmful and misleading to new developers as it contradicts the current architecture.

---

## Appendix: Script File Reference

### `bash-scripts/archive/Create-OIDC-Service-Connection.sh`

*   **Type:** Legacy Setup Script
*   **Purpose:** A complex, all-in-one script for creating an OIDC service connection.
*   **Verdict:** **ARCHIVE**. The process has been simplified and clarified in the `scripts/README.md` guide.

### `pipelines/templates/stage-01-boostrap.yaml`

*   **Type:** Incomplete Stage Template
*   **Purpose:** An alternate, incomplete version of the bootstrap stage template.
*   **Verdict:** **ARCHIVE**. This is a duplicate effort. The correct template is `pipelines/stages/01-bootstrap.stage.yml`.

### `WIKI/00_Overview.md` & `WIKI/02_Getting_Started.md`

*   **Type:** Outdated Documentation
*   **Purpose:** Initial project documentation.
*   **Verdict:** **ARCHIVE**. The information is obsolete and references a Terraform-based approach that is no longer used.

### `README.md` (Root)

*   **Type:** Onboarding Document
*   **Purpose:** To provide a high-level overview and quick-start guide for the entire platform.
*   **Board's Assessment:** "This document is the front door to the project. It should be kept up-to-date and serve as the primary entry point for all engineers."
