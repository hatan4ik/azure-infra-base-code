locals {
  export_name = "cost-export-daily"
}

data "azurerm_client_config" "current" {}

# -------------------------
# Budget at Subscription
# -------------------------
resource "azurerm_consumption_budget_subscription" "sub_budget" {
  name            = "code-runner-budget"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.budget_amount
  time_grain      = "Monthly"
  time_period {
    start_date = formatdate("YYYY-MM-01", timestamp())
    end_date   = "2030-12-31T00:00:00Z"
  }

  dynamic "notification" {
    for_each = var.budget_thresholds
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThan"
      contact_emails = var.budget_contact_emails
    }
  }

  tags = var.common_tags
}

# -------------------------
# Cost Management Export
# -------------------------
data "azurerm_resource_group" "rg_export" {
  name = var.cost_export_storage_rg
}

data "azurerm_storage_account" "export_sa" {
  name                = var.cost_export_storage_account
  resource_group_name = data.azurerm_resource_group.rg_export.name
}

resource "azurerm_cost_management_export" "daily_export" {
  name                     = local.export_name
  scope                    = "/subscriptions/${var.subscription_id}"
  recurrence               = "Daily"
  recurrence_period_start  = formatdate("YYYY-MM-01", timestamp())
  recurrence_period_end    = "2030-12-31T00:00:00Z"
  format                   = "Csv" # or "Parquet"
  time_frame               = "TheLastDay"

  delivery_info {
    destination {
      resource_id     = data.azurerm_storage_account.export_sa.id
      container       = var.cost_export_container
      root_folder_path = "byday"
    }
  }

  depends_on = [azurerm_consumption_budget_subscription.sub_budget]
}

# -------------------------
# (Optional) LA Retention (Doc placeholder; manage in core infra)
# -------------------------
# If you actually manage LA here, replace with a data source + azurerm_log_analytics_workspace table update.
# Shown for pattern documentation only.
