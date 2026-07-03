# Every feature of the module, plus the thing everyone actually wants to see: a real FastAPI
# hello world packaged locally and pushed to the app. The push happens OUTSIDE the app resource
# with one-deploy (az functionapp deployment source config-zip), keyed on the package hash so
# code changes redeploy: the azurerm zip_deploy_file publish path is broken upstream for flex,
# and an ARM-native pull deploy cannot work against keyless storage (one-deploy fetches
# packageUri anonymously; verified live). Applied then destroyed in one CI run.
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

# The local package: the app/ directory (FastAPI + host.json + requirements.txt) zipped by
# Terraform. Flex builds Python dependencies server-side on deploy, so the zip carries source
# only, no vendored site-packages.
data "archive_file" "api_package" {
  type        = "zip"
  source_dir  = "${path.module}/app"
  output_path = "${path.module}/app.zip"
}

# The push: one-deploy via the az CLI, re-run whenever the package hash or the app changes. This
# is the working deploy path for flex today (see the module README for why the in-resource one is
# not), and the CI runner is already logged in via OIDC.
resource "terraform_data" "deploy_api" {
  triggers_replace = [
    data.archive_file.api_package.output_md5,
    module.flex_function_app.function_app_ids[local.api_name],
  ]

  # az exits nonzero on its post-deploy host-key health check under keyless storage even when
  # the deploy lands, so the deploy is failure-tolerant and the real verification is the curl
  # below: the run only passes when FastAPI actually answers.
  provisioner "local-exec" {
    command = "az functionapp deployment source config-zip --resource-group ${local.rg_name} --name ${local.api_name} --src ${data.archive_file.api_package.output_path} || true"
  }

  provisioner "local-exec" {
    command     = "for i in $(seq 1 20); do code=$(curl -s -o /dev/null -w '%%{http_code}' https://${module.flex_function_app.default_hostnames[local.api_name]}/api/hello); echo \"attempt $i: HTTP $code\"; [ \"$code\" = \"200\" ] && exit 0; sleep 15; done; echo 'FastAPI endpoint never answered'; exit 1"
    interpreter = ["/bin/bash", "-c"]
  }
}
