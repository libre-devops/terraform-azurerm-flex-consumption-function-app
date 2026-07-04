# Portal probe: ONE function app on the module's happy path (keyless storage, module-created
# user-assigned identity, auto FC1 plan), plus workspace-based Application Insights and CORS
# opened for the Azure portal so Test/Run works from the Functions blade. Local state, applied
# from the workstation, torn down when the portal session is done. Not part of CI.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-006"
  law_name  = "log-${var.short}-${var.loc}-${terraform.workspace}-006"
  appi_name = "appi-${var.short}-${var.loc}-${terraform.workspace}-006"
  func_name = "func-probe-${var.short}-${var.loc}-${terraform.workspace}-006"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "flex-portal-probe" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "log_analytics" {
  source  = "libre-devops/log-analytics-workspace/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  log_analytics_workspaces = { (local.law_name) = {} }
}

module "application_insights" {
  source  = "libre-devops/application-insights/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  application_insights = {
    (local.appi_name) = {
      workspace_id = module.log_analytics.workspace_ids[local.law_name]
    }
  }
}

module "flex_function_app" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  function_apps = {
    (local.func_name) = {
      runtime_name    = "python"
      runtime_version = "3.12"
      # Everything else is the keyless happy path: shared keys off, identity-authenticated
      # storage, the documented role set granted before the app, host settings wired.

      app_insights_connection_string       = module.application_insights.connection_strings[local.appi_name]
      app_insights_id                      = module.application_insights.ids[local.appi_name]
      grant_app_insights_metrics_publisher = true

      site_config = {
        cors = {
          allowed_origins = ["https://portal.azure.com"]
        }
      }
    }
  }
}

output "function_app_name" {
  value = local.func_name
}

output "default_hostname" {
  value = module.flex_function_app.default_hostnames[local.func_name]
}

output "resource_group_name" {
  value = local.rg_name
}
