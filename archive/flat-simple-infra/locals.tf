locals {
  env_suffix = { dev="d", stage="s", prod="p" }[var.env]
  rg_name = "rg-${var.prefix}-${local.env_suffix}"
  common_tags = merge(var.tags, { env = var.env, project = "example-code-runner" })
  capacity = var.vmss_capacity != null ? var.vmss_capacity : (var.env == "prod" ? 3 : var.env == "stage" ? 2 : 1)
}
