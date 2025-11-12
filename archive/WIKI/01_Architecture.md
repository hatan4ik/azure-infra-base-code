# Architecture

- Self‑hosted VMSS runners in a private VNet (no inbound), static egress via NAT.
- Private Endpoints + Private DNS for ACR, Key Vault, Storage.
- Managed Identity for agents → pull images & fetch secrets.
- OIDC service connection from Azure DevOps to Azure.
- Terraform state in Storage with RBAC and (optionally) private access only.
