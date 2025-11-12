# Example Infrastructure Platform: Component Documentation

This document is the definitive engineering guide for the Example Infrastructure Platform. It is structured chronologically to guide an engineer from core concepts and initial setup through to execution, management, and deep-dive references.

## Table of Contents
[__TOC__]

1.  **Chapter 1: Core Concepts & First-Time Setup**
    *   The Guiding Principles
    *   The "Orchestrator/Template/Script" Architecture
    *   One-Time Setup: Secure Authentication (`scripts/README.md`)
    *   One-Time Setup: Variable Groups (`pipelines/03-var-groups-kve.yaml`)

2.  **Chapter 2: The Main Execution Flow**
    *   The Orchestrator: `pipelines/azure-pipelines.yaml`
    *   Stage 0: Variable Group Setup (`pipelines/stages/00-var-groups.stage.yml`)
    *   Stage 1: Bootstrap (`pipelines/stages/01-bootstrap.stage.yml`)
    *   Stage 2: Core Network (`pipelines/stages/02-vnet-dns-pe.stage.yml`)
    *   Stage 3: Customer Storage (`pipelines/stages/03-customer-storage.stage.yml`)

3.  **Chapter 3: Platform Operations & Management**
    *   Lifecycle Management: `pipelines/90-nuke-core-net.yaml`

4.  **Chapter 4: Developer Utilities**
    *   `pipelines/download-artifacts.sh`
    *   `scripts/devops-pull-repos.sh`
    *   `pipelines/templates/oidc-sanity.yaml`

5.  **Chapter 5: Implementation Script Deep Dive**
    *   `scripts/bootstrap.sh`
    *   `scripts/provision-core-net.sh`

6.  **Appendix A: Legacy & Archived Components**

---

## Chapter 1: Core Concepts & First-Time Setup

Before running any pipeline, it is critical to understand the platform's architecture and perform the initial one-time setup for authentication and configuration.

### The Guiding Principles

All work is guided by three principles:
1.  **Security First:** We eliminate secrets. Authentication is our most critical security boundary.
2.  **Complete Automation:** We codify everything. Manual steps are a failure condition.
3.  **Robustness and Resilience:** Our scripts must be safe to re-run (idempotent).

### The "Orchestrator/Template/Script" Architecture

Our platform follows a modern, three-layer architecture to ensure maintainability and scalability:
1.  **The Orchestrator (`azure-pipelines.yaml`):** The "maestro." Its only job is to define the sequence of stages and pass parameters. It contains no logic.
2.  **Stage Templates (`pipelines/stages/*.yml`):** The "blueprints." Each template defines the jobs for a single stage and calls the appropriate script.
3.  **Implementation Scripts (`scripts/*.sh`):** The "workers." These are standalone, idempotent shell scripts where all the real work happens.

### One-Time Setup: Secure Authentication

*   **File:** `scripts/README.md`
*   **Purpose:** This is the most important document for getting started. It provides the definitive, step-by-step guide for setting up the secure, secret-less **Workload Identity Federation (OIDC)** service connection.
*   **Action:** Follow this guide precisely to create the `My-ARM-Connection-OIDC` service connection. This is a mandatory prerequisite for all pipelines.

### One-Time Setup: Variable Groups

*   **File:** `pipelines/03-var-groups-kve.yaml`
*   **Purpose:** This is the single source of truth for all pipeline configuration. It is an idempotent management pipeline that creates or updates all Azure DevOps Variable Groups required by the platform.
*   **Action:** Run this pipeline manually from the Azure DevOps UI once after setting up authentication. It will create `vg-core-bootstrap`, `vg-core-network`, `vg-customer-washington`, and the Key Vault-backed `vg-kv-backend`.
*   **Design Notes:** This is the most sophisticated piece of automation in the repository. The `upsert_classic` and `upsert_kv` functions query the ADO REST API before deciding to `POST` (create) or `PUT` (update), making it perfectly idempotent. The use of `jq` to safely construct JSON payloads is a best practice that avoids brittle string quoting.

---

## Chapter 2: The Main Execution Flow

This section describes the main end-to-end pipeline and the stages it orchestrates.

### The Orchestrator: `pipelines/azure-pipelines.yaml`

*   **Type:** Main Orchestrator Pipeline
*   **Purpose:** To define the end-to-end deployment sequence for the entire platform. It does no work itself; it only calls stage templates in the correct order, passing the necessary parameters and variable groups.
*   **Execution:** This is the primary pipeline to be run manually from the Azure DevOps UI after the one-time setup is complete.
*   **Current State:** This pipeline is currently **non-functional**. It references templates with incorrect paths (e.g., `stages//` with a double slash) and the `scriptsDir` variable points to a non-existent nested path. These must be corrected for the pipeline to work.

### Stage 0: Variable Group Setup (`pipelines/stages/00-var-groups.stage.yml`)

*   **Type:** Optional Stage Template
*   **Purpose:** A wrapper stage that calls the `scripts/create_var_groups.sh` script. It is toggled by the `RUN_VARS_SETUP` variable in the main pipeline.
*   **Execution:** Called by `azure-pipelines.yaml` if `RUN_VARS_SETUP: 'true'`.
*   **Design Notes:** This stage and its underlying script (`create_var_groups.sh`) are considered **legacy**. The `pipelines/03-var-groups-kve.yaml` pipeline is far more capable and is the recommended method for managing variable groups.

### Stage 1: Bootstrap (`pipelines/stages/01-bootstrap.stage.yml`)

*   **Type:** Stage Template
*   **Purpose:** To define the "Bootstrap" stage of the pipeline. It sets up the deployment job, environment, and variable groups, and then calls the `bootstrap.sh` script to perform the actual work.
*   **Execution:** Called by `azure-pipelines.yaml`. Not intended to be run directly.
*   **Outputs:** Core Azure resources like the state Resource Group, Key Vault, Log Analytics Workspace, and Container Registry.
*   **Design Notes:** This is a perfect example of a modern stage template. It's declarative and reusable. However, the file has a structural flaw: it is defined with a top-level `stages:` block, making it a multi-stage template. It must be refactored to be a single-stage template by removing the `stages:` wrapper to be correctly consumed by the main pipeline.

### Stage 2: Core Network (`pipelines/stages/02-vnet-dns-pe.stage.yml`)

*   **Type:** Stage Template
*   **Purpose:** To define the "Core Network" stage. It orchestrates the execution of the `vnet_dns_pe.sh` script (which in turn calls `core-net.sh`) to provision the VNet, subnets, and Private DNS zones.
*   **Execution:** Called by `azure-pipelines.yaml`.
*   **Outputs:** Core Azure networking resources.
*   **Design Notes:** This template follows the modern pattern correctly. However, the use of a `vnet_dns_pe.sh` shim script to call `core-net.sh` is an unnecessary layer of indirection. The template should be simplified to call `core-net.sh` directly.

### Stage 3: Customer Storage (`pipelines/stages/03-customer-storage.stage.yml`)

*   **Type:** Stage Template
*   **Purpose:** To define the "Customer Storage" stage. It orchestrates the execution of the `customer-storage.sh` script to provision ADLS Gen2 storage for a specific customer.
*   **Execution:** Called by `azure-pipelines.yaml`.
*   **Outputs:** An Azure Data Lake Storage account with associated containers, diagnostics, RBAC, and Private Endpoints.
*   **Design Notes:** This is a well-designed, reusable component that correctly follows our target architecture.

---

## Chapter 3: Platform Operations & Management

These pipelines are used for ongoing management tasks outside of the main deployment flow.

### `pipelines/90-nuke-core-net.yaml`

*   **Type:** Lifecycle/Teardown Pipeline
*   **Purpose:** To safely and completely destroy the core network and its dependencies. This is critical for managing non-production environments and controlling costs.
*   **Execution:** Run manually with extreme caution.
*   **Inputs:**
    *   **Variables:** `CONFIRM_NUKE` must be set to `YES` to proceed. `DRY_RUN` can be set to `true` to preview actions.
*   **Outputs:** Deletes Private Endpoints, resource locks, and the core network resource group.
*   **Design Notes:** The existence of this script is a mark of a mature and professional operation. It correctly handles dependencies (like PEs in other RGs) and includes safety switches.

---

## Chapter 4: Developer Utilities

These scripts and templates support the development and troubleshooting lifecycle.

### `pipelines/download-artifacts.sh`

*   **Type:** Local Utility Script
*   **Purpose:** Allows a developer to easily download the `network-outputs` artifact from the latest successful pipeline run.
*   **Execution:** Run locally from a developer's machine.

### `scripts/devops-pull-repos.sh`

*   **Type:** Local Utility Script
*   **Purpose:** A helper script for developers to clone all repositories from the configured Azure DevOps project.
*   **Execution:** Run locally to set up a new development environment.

### `pipelines/templates/oidc-sanity.yaml`

*   **Type:** Utility Job Template
*   **Purpose:** To provide a reusable, self-contained job that verifies the Workload Identity Federation (OIDC) connection is working correctly. It fetches a real OIDC token and validates its claims against the service connection's expected values.
*   **Execution:** Can be included in any pipeline to diagnose authentication issues.
*   **Design Notes:** This is a brilliant piece of engineering. It provides an automated way to build confidence in our most critical security component and dramatically speeds up troubleshooting.

---

## Chapter 5: Implementation Script Deep Dive

This section provides a detailed reference for the core implementation scripts.

### `scripts/bootstrap.sh`

*   **Type:** Core Logic Script
*   **Purpose:** To idempotently create and configure all foundational resources: the state Resource Group, Storage Account for Terraform state, a hardened Key Vault, a Log Analytics Workspace, and an Azure Container Registry. It also assigns necessary RBAC roles to the Managed Identity.
*   **Execution:** Called by the `01-bootstrap.stage.yml` template.
*   **Design Notes:** This script is well-written and robust. Its use of `if ! az ... show` checks makes it safely re-runnable. However, its **duplication** in `pipelines/bootstrap.sh` and `pipelines/vars/bootstrap.sh` is a critical flaw that must be resolved immediately. There should be a single, canonical version of this file at `scripts/bootstrap.sh`.

### `scripts/provision-core-net.sh`

*   **Type:** Core Logic Script
*   **Purpose:** To idempotently create and configure the core network, including the VNet, subnets (`workloads` and `private-endpoints`), and all necessary Private DNS Zones. It contains intelligent logic to re-calculate subnet CIDRs if the requested ranges don't fit in the VNet's address space. It also supports creating a NAT Gateway.
*   **Execution:** Called by a network stage template (e.g., the legacy `02-vnet-dns-pe.yaml`).
*   **Design Notes:** This is a highly advanced and resilient script. The Python-based CIDR calculation is a clever solution to a common networking challenge. This script is production-ready and should be the standard for network provisioning.

---

## Appendix A: Legacy & Archived Components

----
----
----
These files represent past iterations. They should be considered **read-only** and are candidates for deletion to complete the repository's refactoring.


