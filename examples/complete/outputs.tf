output "api_url" {
  description = "The FastAPI hello world endpoint, live once the pipeline's deploy stage has pushed the app/ package."
  value       = "https://${module.flex_function_app.default_hostnames[local.api_name]}/api/hello"
}

output "function_app_ids_zipmap" {
  description = "Map of app name to { name, id }."
  value       = module.flex_function_app.function_app_ids_zipmap
}

output "identity_principal_ids" {
  description = "Per-app identity principal ids."
  value       = module.flex_function_app.identity_principal_ids
}

output "service_plan_ids" {
  description = "Map of plan key to id (the shared plan from the map)."
  value       = module.flex_function_app.service_plan_ids
}
