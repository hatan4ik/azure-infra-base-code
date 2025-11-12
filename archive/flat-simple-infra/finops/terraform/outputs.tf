output "budget_id" {
  value       = azurerm_consumption_budget_subscription.sub_budget.id
  description = "Budget resource id"
}
output "cost_export_name" {
  value       = azurerm_cost_management_export.daily_export.name
  description = "Cost export job name"
}
