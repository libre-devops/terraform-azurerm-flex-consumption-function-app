# Every feature of the module's INFRASTRUCTURE surface: a shared plan hosting two apps (keyless
# identity auth and the keys-on opt-out side by side), Application Insights with AAD ingestion,
# scale tuning, and site_config. Code deployment deliberately does NOT happen in this apply: this
# repo's CI deploys the app/ package in a dedicated stage with a fresh login (see the repo README,
# "A different workflow, on purpose"), because tokens expire mid-apply and the ARM pull path
# cannot be keyless. Applied then destroyed in one CI run.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"
  law_name  = "log-${var.short}-${var.loc}-${terraform.workspace}-002"
  appi_name = "appi-${var.short}-${var.loc}-${terraform.workspace}-002"
  api_name  = "func-api-${var.short}-${var.loc}-${terraform.workspace}-002"
  wkr_name  = "func-wkr-${var.short}-${var.loc}-${terraform.workspace}-002"
  plan_name = "asp-shared-${var.short}-${var.loc}-${terraform.workspace}-002"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "terraform-azurerm-flex-consumption-function-app" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

# Workspace-based Application Insights for the API app, from the released modules.
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

  # A shared plan from the map: flex is commonly one app per plan, but the module does not force
  # that; app_service_environment_id is the ASE hook when you have one.
  service_plans = {
    (local.plan_name) = {
      sku_name = "FC1"
    }
  }

  function_apps = {
    # The API: keyless identity-authenticated storage (the secure default), Application Insights
    # with AAD ingestion (the Monitoring Metrics Publisher grant and auth string are wired
    # because the module knows the AI scope and owns the identity), scale tuned, and the FastAPI
    # package below pushed to it.
    (local.api_name) = {
      runtime_name     = "python"
      runtime_version  = "3.12"
      service_plan_key = local.plan_name

      app_insights_connection_string       = module.application_insights.connection_strings[local.appi_name]
      app_insights_id                      = module.application_insights.ids[local.appi_name]
      grant_app_insights_metrics_publisher = true

      maximum_instance_count = 40
      instance_memory_in_mb  = 2048
      http_concurrency       = 16

      site_config = {
        minimum_tls_version = "1.3"

        cors = {
          allowed_origins = ["https://portal.azure.com"]
        }
      }

      tags = { Component = "api" }
    }

    # The worker: same shared plan, keys-on connection string storage auth (the documented
    # opt-out for apps that need function-key trigger auth), an always-ready instance, and a
    # deliberately different runtime.
    (local.wkr_name) = {
      runtime_name     = "node"
      runtime_version  = "20"
      service_plan_key = local.plan_name

      storage_shared_access_key_enabled = true
      storage_authentication_type       = "StorageAccountConnectionString"
      create_user_assigned_identity     = false
      identity                          = { type = "SystemAssigned" }

      always_ready = [
        { name = "http", instance_count = 1 }
      ]

      tags = { Component = "worker" }
    }
  }
}


