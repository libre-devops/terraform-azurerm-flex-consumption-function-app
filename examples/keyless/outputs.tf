output "api_url" {
  description = "The FastAPI hello world endpoint, live once the deploy stage has pushed the package."
  value       = "https://${module.flex_function_app.default_hostnames[local.func_name]}/api/hello"
}

output "function_app_name" {
  description = "The app name the deploy stage targets."
  value       = local.func_name
}

output "resource_group_name" {
  description = "The resource group the deploy stage targets."
  value       = local.rg_name
}
