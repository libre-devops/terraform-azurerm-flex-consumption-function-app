<!--
  Header for the complete example README. Edit this file, then run `just docs`
  (or ./Sort-LdoTerraform.ps1 -IncludeExamples) to regenerate the section between the markers.
  The example's main.tf is embedded into the README automatically (see .terraform-docs.yml).
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Complete example

Every feature of the module, plus the full deploy flow: a shared plan hosting two apps (keyless
identity auth and the keys-on connection-string opt-out side by side), Application Insights with
AAD ingestion wired by the module, and a local FastAPI hello world packaged by Terraform and
pushed with one-deploy, verified live by curling the endpoint until it answers. Run it with
`just e2e complete`, which applies the stack then always destroys it.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)

<!-- BEGIN_TF_DOCS -->
## Example configuration

```hcl
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
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.0.0, < 3.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | >= 2.0.0, < 3.0.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_application_insights"></a> [application\_insights](#module\_application\_insights) | libre-devops/application-insights/azurerm | ~> 4.0 |
| <a name="module_flex_function_app"></a> [flex\_function\_app](#module\_flex\_function\_app) | ../../ | n/a |
| <a name="module_log_analytics"></a> [log\_analytics](#module\_log\_analytics) | libre-devops/log-analytics-workspace/azurerm | ~> 4.0 |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | ~> 4.0 |
| <a name="module_tags"></a> [tags](#module\_tags) | libre-devops/tags/azurerm | ~> 4.0 |

## Resources

| Name | Type |
|------|------|
| [terraform_data.deploy_api](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [archive_file.api_package](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deployed_branch"></a> [deployed\_branch](#input\_deployed\_branch) | Git branch the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_branch. | `string` | `""` | no |
| <a name="input_deployed_repo"></a> [deployed\_repo](#input\_deployed\_repo) | Repository URL the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_repo. | `string` | `""` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | Outfix: short Azure region code used in resource names (for example uks). | `string` | `"uks"` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Map of short region codes to Azure region slugs. | `map(string)` | <pre>{<br/>  "eus": "eastus",<br/>  "euw": "westeurope",<br/>  "uks": "uksouth",<br/>  "ukw": "ukwest"<br/>}</pre> | no |
| <a name="input_short"></a> [short](#input\_short) | Infix: short product code used in resource names. | `string` | `"ldo"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_url"></a> [api\_url](#output\_api\_url) | The FastAPI hello world endpoint, live once the pipeline's deploy stage has pushed the app/ package. |
| <a name="output_function_app_ids_zipmap"></a> [function\_app\_ids\_zipmap](#output\_function\_app\_ids\_zipmap) | Map of app name to { name, id }. |
| <a name="output_identity_principal_ids"></a> [identity\_principal\_ids](#output\_identity\_principal\_ids) | Per-app identity principal ids. |
| <a name="output_service_plan_ids"></a> [service\_plan\_ids](#output\_service\_plan\_ids) | Map of plan key to id (the shared plan from the map). |
<!-- END_TF_DOCS -->
