# FinOps

- VMSS autoscale by queue length/time windows (not included in code; recommend adding autoscale rules).
- Choose **Standard** ACR for dev/stage; **Premium** only if needed (geo‑replication, throughput).
- Right‑size VMSS (D2s_v5 dev/stage; D4s_v5 prod).
- Turn on diagnostics: cost allocation tags are included (`org`, `environment`); export daily to cost mgmt.
