# Managing Azure DevOps Service Connections

This repository contains a set of scripts for creating and managing service connections between Azure DevOps (ADO) and Microsoft Azure.

The primary goal is to establish a secure, automated way for ADO pipelines to authenticate and deploy resources to Azure.

---

## TL;DR: The Recommended Method

For all new connections, use **Workload Identity Federation (WIF)** with a pre-existing **User-Assigned Managed Identity**. This method is passwordless, highly secure, and aligns with modern cloud best practices.

1.  **Ensure the Managed Identity exists:**
    ```bash
    # This is a one-time setup for your environment.
    az group create --name "rg-ado-wif" --location "eastus"
    az identity create --name "ado-wif-mi" --resource-group "rg-ado-wif"
    ```

2.  **Grant it permissions (Example: Contributor on a resource group):**
    ```bash
    # Get the Principal ID of the Managed Identity
    MI_PRINCIPAL_ID=$(az identity show -n "ado-wif-mi" -g "rg-ado-wif" --query principalId -o tsv)

    # Assign 'Contributor' role on a specific resource group scope
    az role assignment create \
      --assignee "$MI_PRINCIPAL_ID" \
      --role "Contributor" \
      --scope "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/YOUR_TARGET_RESOURCE_GROUP"
    ```

3.  **Run the creation script:** This script creates the ADO Service Connection and tells you the final command to run to establish the trust relationship.
    ```bash
    ./create-oidc-connection-from-mi.sh
    ```

4.  **Run the final command** provided by the script's output to create the federated credential in Azure.

---

## Table of Contents

1.  [Strategic Recommendation: The Proper Way](#strategic-recommendation-the-proper-way)
2.  [Process: Creating a WIF/OIDC Connection](#process-creating-a-wifoidc-connection)
    - [Phase 1: Create the Azure Identity](#phase-1-create-the-azure-identity-the-who)
    - [Phase 2 & 3: Create the Connection and Trust](#phase-2--3-create-the-ado-connection-and-federated-trust)
3.  [Cleanup Operations](#cleanup-operations)
    - [Cleaning up the Recommended OIDC Connection](#cleaning-up-the-recommended-oidc-connection)
    - [Cleaning up the Legacy Secret-Based Connection](#cleaning-up-the-legacy-secret-based-connection)
4.  [Legacy Method (Secret-Based - Discouraged)](#legacy-method-secret-based---discouraged)
5.  [Script Reference](#script-reference)

---

## Strategic Recommendation: The Proper Way

The most secure, scalable, and maintainable method for connecting Azure DevOps to Azure is **Workload Identity Federation (OIDC)**. This approach eliminates the need for storing and managing client secrets (passwords) for service principals.

*   **Why it's better:**
    *   **No Secrets:** Eliminates the risk of leaked credentials.
    *   **No Rotation:** No need to manually rotate secrets before they expire.
    *   **Least Privilege:** Works perfectly with a Managed Identity that has narrowly-scoped permissions.

We strongly recommend using a central **User-Assigned Managed Identity** as the identity for your CI/CD system. The scripts in this repository are built around this best practice, using an identity named `ado-wif-mi`.

## Process: Creating a WIF/OIDC Connection

This process is broken into distinct phases, separating the responsibilities of an Azure Administrator and a DevOps Engineer.

### Phase 1: Create the Azure Identity (The "Who")

An Azure Administrator should perform this one-time setup. We create a User-Assigned Managed Identity that will represent our CI/CD system in Azure.

1.  **Create the Resource Group and Managed Identity:**
    ```bash
    az group create --name "rg-ado-wif" --location "eastus"
    az identity create --name "ado-wif-mi" --resource-group "rg-ado-wif"
    ```

2.  **Assign Permissions (Principle of Least Privilege):** Grant this identity only the permissions it needs. **Do not use `Owner` on the subscription.**

    *Example: Grant `Contributor` on a single resource group.*
    ```bash
    MI_PRINCIPAL_ID=$(az identity show -n "ado-wif-mi" -g "rg-ado-wif" --query principalId -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)

    az role assignment create \
      --assignee "$MI_PRINCIPAL_ID" \
      --role "Contributor" \
      --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/my-app-resource-group"
    ```

### Phase 2 & 3: Create the ADO Connection and Federated Trust

A DevOps Engineer can now use a script to create the connection and establish the trust relationship.

1.  **Run the creation script:**
    This script creates the service connection in Azure DevOps and generates the necessary `issuer` and `subject` claims.
    ```bash
    ./create-oidc-connection-from-mi.sh
    ```

2.  **Run the output command:**
    The script will output an `az identity federated-credential create` command. Copy, paste, and run this command in your terminal. This completes the setup by telling Azure to trust tokens from your ADO service connection.

## Cleanup Operations

### Cleaning up the Recommended OIDC Connection

To undo the creation process, you need to remove the federated credential from the Managed Identity and delete the service connection from Azure DevOps.

Run the `cleanup-oidc-mi-connection.sh` script. It will automatically find and delete the federated credential and the ADO service connection.

```bash
./cleanup-oidc-mi-connection.sh
```

> **Note:** This script intentionally does **not** delete the Managed Identity (`ado-wif-mi`) or its role assignments, as they may be shared. To fully remove the identity, you must delete it manually from the Azure portal or via the CLI.

### Cleaning up the Legacy Secret-Based Connection

If you created a connection using `admin-fc-creator.sh`, you can clean it up using its corresponding cleanup script. This will delete the ADO service connection, the Azure Service Principal, its role assignment, and the underlying AD Application.

```bash
./cleanup-admin-fc.sh
```

## Legacy Method (Secret-Based - Discouraged)

The `admin-fc-creator.sh` script demonstrates the classic, secret-based method of creating a service connection.

*   **What it does:** Creates a Service Principal with an `Owner` role and a 1-year client secret, then stores that secret in Azure DevOps.
*   **Why you should avoid it:**
    *   **Security Risk:** The client secret is a powerful, long-lived password that can be leaked.
    *   **Management Overhead:** The secret must be manually rotated before it expires, or pipelines will fail.
    *   **Over-privileged:** It grants the `Owner` role, violating the Principle of Least Privilege.

This method should not be used for any new development.

## Script Reference

| Script | Description |
|---|---|
| `create-oidc-connection-from-mi.sh` | **(Recommended)** Creates a WIF/OIDC connection using a pre-existing Managed Identity. |
| `cleanup-oidc-mi-connection.sh` | **(Recommended)** Cleans up the connection and federation created by the script above. |
| `admin-fc-creator.sh` | (Legacy) Creates a secret-based service connection with an `Owner` role. **Do not use.** |
| `cleanup-admin-fc.sh` | (Legacy) Cleans up all resources created by `admin-fc-creator.sh`. |
| `service-connection-create-new.sh` | (Complex) An all-in-one script that creates a *new* SP and a WIF connection. Prefer the Managed Identity approach. |
| `cleanup-oidc-sc.sh` | Cleans up the resources created by `service-connection-create-new.sh`. |
| `Create-OIDC-Service-Connection.sh` | A more complex version of the recommended script. Prefer `create-oidc-connection-from-mi.sh` for clarity. |