output "default_hostnames" {
  description = "Map of app name to its default hostname (https://<hostname> is the app's base URL)."
  value       = { for k, a in azurerm_function_app_flex_consumption.this : k => a.default_hostname }
}

output "function_app_ids" {
  description = "Map of app name to its id."
  value       = { for k, a in azurerm_function_app_flex_consumption.this : k => a.id }
}

output "function_app_ids_zipmap" {
  description = "Map of app name to { name, id }, for easy composition with other modules."
  value       = { for k, a in azurerm_function_app_flex_consumption.this : k => { name = a.name, id = a.id } }
}

output "function_apps" {
  description = "Map of app name to the full flex consumption app object. Sensitive as a whole because the object carries storage_access_key and the site credentials; the ids, hostnames, and identity maps below stay plain for composition."
  value       = azurerm_function_app_flex_consumption.this
  sensitive   = true
}

output "identity_principal_ids" {
  description = "Map of app name to { system_assigned, user_assigned } principal ids (nulls where an identity kind is absent)."
  value = {
    for k, a in azurerm_function_app_flex_consumption.this : k => {
      system_assigned = try(a.identity[0].principal_id, null)
      user_assigned   = try(azurerm_user_assigned_identity.this[k].principal_id, null)
    }
  }
}

output "possible_outbound_ip_address_lists" {
  description = "Map of app name to the app's possible outbound IPs: the allow-list for locking the backing storage down after create (see the complete example)."
  value       = { for k, a in azurerm_function_app_flex_consumption.this : k => a.possible_outbound_ip_address_list }
}

output "service_plan_ids" {
  description = "Map of plan key (from service_plans plus the dedicated asp-<app> plans) to its id."
  value = merge(
    { for k, p in azurerm_service_plan.this : k => p.id },
    { for k, p in azurerm_service_plan.auto : "asp-${k}" => p.id },
  )
}

output "storage_account_ids" {
  description = "Map of app name to the created storage account id (only apps with created storage)."
  value       = { for k, s in azurerm_storage_account.this : k => s.id }
}

output "storage_container_endpoints" {
  description = "Map of app name to the deployment container endpoint the app runs from."
  value       = local.storage_container_endpoints
}

output "user_assigned_identity_ids" {
  description = "Map of app name to the module-created user assigned identity id (only apps with create_user_assigned_identity)."
  value       = { for k, i in azurerm_user_assigned_identity.this : k => i.id }
}
