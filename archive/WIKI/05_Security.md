# Security

- OIDC service connection (no SP secrets).
- Managed Identity for VMSS agents (AcrPull, KV Secrets User).
- Private Endpoints + Private DNS for ACR/KV/Storage; disable public access.
- Defender for Cloud enabled via **example.defender** module (ContainerRegistry, VMs).
- NSGs deny inbound; NAT GW offers static egress.
- No secrets in YAML; Key Vault only.
