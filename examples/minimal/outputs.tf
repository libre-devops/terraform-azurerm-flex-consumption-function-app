output "default_hostnames" {
  description = "Map of app name to default hostname."
  value       = module.flex_function_app.default_hostnames
}

output "function_app_ids" {
  description = "Map of app name to id."
  value       = module.flex_function_app.function_app_ids
}
