variable "subscription_id" {
  type        = string
  description = "Target subscription for budgets and policy"
}

variable "budget_amount" {
  type        = number
  description = "Monthly budget amount in USD"
  default     = 300
}

variable "budget_contact_emails" {
  type        = list(string)
  description = "Emails to notify on budget thresholds"
  default     = []
}

variable "budget_thresholds" {
  type        = list(number)
  description = "Budget thresholds as percentages [50, 80, 100, 120]"
  default     = [50, 80, 100, 120]
}

variable "cost_export_storage_rg" {
  type        = string
  description = "Resource group of the storage account for cost exports"
}

variable "cost_export_storage_account" {
  type        = string
  description = "Storage account for cost exports"
}

variable "cost_export_container" {
  type        = string
  description = "Blob container for cost exports"
  default     = "cmexports"
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Optional Log Analytics workspace id to set retention (documented; manage LA in core infra)"
  default     = ""
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Retention in days for LA (keep small; export old to blob)"
  default     = 30
}

variable "common_tags" {
  type = map(string)
  default = {
    owner      = "platform"
    costCenter = "cloud-core"
    env        = "shared"
  }
}
