# Troubleshooting

- Agent not registering: check cloud‑init logs on VMSS instance (`/var/log/cloud-init-output.log`).
- Remote state errors: validate Storage firewall/PE and RBAC.
- KV access denied: ensure `Key Vault Secrets User` for the agent MI.
- Private DNS resolution: confirm VNet links in `example.privatelink`.
