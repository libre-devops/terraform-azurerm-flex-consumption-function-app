<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform Azure Flex Consumption Function App

Azure Functions Flex Consumption done properly: keyless identity auth wired end to end, plans and
storage that flex with you, and a deploy story that actually works.

[![CI](https://github.com/libre-devops/terraform-azurerm-flex-consumption-function-app/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azurerm-flex-consumption-function-app/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azurerm-flex-consumption-function-app?sort=semver&label=release)](https://github.com/libre-devops/terraform-azurerm-flex-consumption-function-app/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azurerm-flex-consumption-function-app)](./LICENSE)

---

## Overview

Flex consumption is a massive resource with sharp edges, and this module took the live bruises so
you do not have to. Fast to get going: an entry with nothing but a runtime gets a dedicated FC1
plan, keyless storage with a deployment container, a user-assigned identity granted the full
documented role set BEFORE the app exists (system-assigned plus deploy-during-create is a
bootstrap deadlock), and the identity host storage settings wired automatically. Flexible when it
matters: every one of those defaults has an explicit override.

- **Keyless by default, correctly.** `shared_access_key_enabled = false` with the complete
  documented recipe: Storage Blob Data Owner (the host's secrets store) plus Blob, Queue, and
  Table Contributor for the identity, and `AzureWebJobsStorage__accountName` /
  `__credential = managedidentity` / `__clientId` app settings. One documented limitation,
  verified live: the host and function keys API is unavailable keyless, so use anonymous or AAD
  (Easy Auth) trigger auth, or flip keys on (the connection-string opt-out is first class).
- **Plans as a map, not a straitjacket.** Multiple apps can share a plan, `sku_name` is not
  welded to FC1, and `app_service_environment_id` is there for ASE placement. Apps that reference
  no plan get a dedicated FC1 plan automatically.
- **Storage in three shapes.** Created (default, secure defaults throughout), bring-your-own
  account by id (the module still builds the container and still grants the roles, because it has
  the scope), or a raw container endpoint escape hatch where the caller owns all wiring.
- **A deploy story that works today.** The provider's `zip_deploy_file` publish path is broken
  upstream for flex (its status poll 404s on healthy apps), and an ARM-native pull deploy cannot
  work against keyless storage (one-deploy fetches `packageUri` anonymously; verified live). The
  supported pattern is pushing the package with one-deploy from outside the resource, and the
  complete example shows it end to end: a real FastAPI app zipped by Terraform and pushed with
  `az functionapp deployment source config-zip`, keyed on the package hash, verified by curling
  the endpoint. `zip_deploy_file` stays as a passthrough for when upstream fixes it (a check
  steers you away meanwhile).
- **Application Insights, AAD-ingestion ready.** Pass the connection string and the AI resource
  id and the module wires the app setting, the AAD ingestion auth string, and the Monitoring
  Metrics Publisher grant.
- **The full resource surface.** Both auth_settings trees, site_config with CORS and IP
  restrictions, always-ready instances, sticky settings, connection strings, client certificates,
  VNet integration, and plan-time enforcement of the rules ARM only tells you about at apply
  (storage auth pairings, the flex instance memory sizes, CORS wildcard versus credentials).

Requires Terraform >= 1.9 and azurerm >= 4.0.

## Usage

```hcl
module "flex_function_app" {
  source  = "libre-devops/flex-consumption-function-app/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids["rg-ldo-uks-prd-001"]
  location          = "uksouth"
  tags              = module.tags.tags

  function_apps = {
    "func-api-ldo-uks-prd-001" = {
      runtime_name    = "python"
      runtime_version = "3.12"

      app_insights_connection_string = module.application_insights.connection_strings["appi-ldo-uks-prd-001"]
      app_insights_id                = module.application_insights.ids["appi-ldo-uks-prd-001"]
    }
  }
}
```

## Examples

- [`examples/minimal`](./examples/minimal) - one entry, nothing but a runtime: the whole secure
  stack arrives by default.
- [`examples/complete`](./examples/complete) - the full infrastructure surface: a shared plan
  hosting two apps (keyless identity auth and the keys-on opt-out side by side), Application
  Insights with AAD ingestion, scale tuning, and site_config; its FastAPI package deploys in the
  pipeline's deploy stage.
- [`examples/keyless`](./examples/keyless) - the total-automated-keyless-deployment showcase: no
  keys, no SAS, anywhere.
- [`examples/offline-package`](./examples/offline-package) - the vendored-wheels pattern for
  egress-blocked apps: pip installs into `.python_packages/lib/site-packages` on the runner, the
  package ships byte-identical, nothing builds server-side.
- [`examples/powershell`](./examples/powershell) - the PowerShell worker on the same secure stack
  (`run.ps1` + `function.json`, no build step, an empty `requirements.psd1` so the app needs no
  gallery access at runtime).

## Developing

Local work needs **PowerShell 7+** and **[`just`](https://github.com/casey/just)**, because the recipes
wrap the [LibreDevOpsHelpers](https://www.powershellgallery.com/packages/LibreDevOpsHelpers)
PowerShell module (the same engine the `libre-devops/terraform-azure` action runs in CI). Install
just with `brew install just`, or `uv tool add rust-just` then `uv run just <recipe>`.

Run `just` to list recipes: `just update-ldo-pwsh` (install or force-update LibreDevOpsHelpers from
PSGallery), `just validate`, `just scan` (Trivy only), `just pwsh-analyze` (PSScriptAnalyzer only),
`just plan`, `just apply`, `just destroy`, `just e2e`, `just test`, and `just docs` (the
plan/apply/destroy recipes mirror the action, including the storage firewall dance; `just e2e`
applies an example then always destroys it, defaulting to `minimal`, so nothing is left running).
Releasing is also `just`:
`just increment-release [patch|minor|major]` bumps, tags, and publishes a GitHub release, and the
Terraform Registry picks up the tag.

## Security scan exceptions

This module is scanned with [Trivy](https://github.com/aquasecurity/trivy); HIGH and CRITICAL
findings fail the build. Any waiver is a deliberate, reviewed decision, never a way to quiet a
finding that should be fixed. Waivers live in a `.trivyignore.yaml` (the machine-applied source of
truth, passed to Trivy with `--ignorefile`) and are mirrored in a table here so the reason is
auditable.

| ID | Scope | Reason |
| --- | --- | --- |
| AVD-AZU-0012 (storage network rules) | module-created storage accounts | Not fixable with IP rules, proven live: default-Deny with the app's own possible outbound IPs allow-listed 403s the deployment service and 503s the running host, because flex reaches storage from platform ranges. The working lockdown is VNet integration plus service or private endpoints, expressed through the per-app `storage_network_rules` input. |
| AVD-AZU-0060 (customer-managed keys) | module-created storage accounts | Deliberate non-goal for deployment package storage; platform-managed keys plus default infrastructure (double) encryption are the accepted posture. |
| AVD-AZU-0057 (storage analytics logging) | module-created storage accounts | Superseded by diagnostic settings, which belong to the caller's observability topology (the diagnostic-settings module). |

## Reference

The Requirements, Providers, Inputs, Outputs, and Resources below are generated by `terraform-docs`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_function_app_flex_consumption.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/function_app_flex_consumption) | resource |
| [azurerm_role_assignment.app_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.storage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_service_plan.auto](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan) | resource |
| [azurerm_service_plan.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_function_apps"></a> [function\_apps](#input\_function\_apps) | Flex consumption function apps keyed by name. Fast to get going: an entry with just runtime\_name<br/>and runtime\_version gets a dedicated FC1 plan, a keyless storage account with a deployment<br/>container, a user-assigned identity granted the full documented role set, and the identity-based<br/>host storage app settings wired automatically. Flexible when it matters: every default has an<br/>explicit override.<br/><br/>PLAN: exactly one of service\_plan\_key (a plan from service\_plans), service\_plan\_id (bring your<br/>own), or neither (dedicated FC1 plan created).<br/><br/>STORAGE, three shapes: created (default), bring-your-own account via storage\_account\_id (the<br/>module still builds the container and can still grant roles because it has the scope), or the raw<br/>storage\_container\_endpoint escape hatch (no grants, caller owns all wiring).<br/>storage\_shared\_access\_key\_enabled defaults FALSE (keyless): deploys and runtime work with<br/>identity auth, with one documented limitation: the host and function keys API is unavailable, so<br/>keyless apps should use anonymous or AAD (Easy Auth) trigger auth; set it true if you need<br/>function-key auth. When keyless identity auth is active the module wires<br/>AzureWebJobsStorage\_\_accountName/\_\_credential/\_\_clientId automatically<br/>(wire\_host\_storage\_settings = false to opt out).<br/><br/>IDENTITY: the module creates a user-assigned identity per app by default<br/>(create\_user\_assigned\_identity), because system-assigned plus deploy-during-create is a bootstrap<br/>deadlock (the grant needs the principal id, the deploy needs the grant). Pass identity to bring<br/>your own (the module then grants nothing on storage: the identity owner does).<br/><br/>DEPLOY: push the package from outside the resource with one-deploy (see the complete example:<br/>archive\_file plus az functionapp deployment source config-zip keyed on the package hash). The<br/>azurerm zip\_deploy\_file publish path is broken upstream for flex and stays as a passthrough; an<br/>ARM-native pull deploy cannot work keyless because one-deploy fetches packageUri anonymously.<br/><br/>APP INSIGHTS: pass app\_insights\_connection\_string to wire the app setting; with an app\_insights\_id<br/>and a module-created identity the AAD ingestion auth string and Monitoring Metrics Publisher<br/>grant are wired too. | <pre>map(object({<br/>    runtime_name    = string<br/>    runtime_version = string<br/><br/>    service_plan_key = optional(string)<br/>    service_plan_id  = optional(string)<br/><br/>    # Storage (three shapes; see description).<br/>    create_storage_account                    = optional(bool, true)<br/>    storage_account_name                      = optional(string)<br/>    storage_account_id                        = optional(string)<br/>    storage_container_endpoint                = optional(string)<br/>    storage_container_name                    = optional(string, "app-packages")<br/>    storage_shared_access_key_enabled         = optional(bool, false)<br/>    storage_infrastructure_encryption_enabled = optional(bool, true)<br/>    storage_authentication_type               = optional(string)<br/>    storage_access_key                        = optional(string)<br/>    storage_role_names                        = optional(list(string), ["Storage Blob Data Owner", "Storage Blob Data Contributor", "Storage Queue Data Contributor", "Storage Table Data Contributor"])<br/>    storage_account_replication_type          = optional(string, "LRS")<br/>    storage_network_rules = optional(object({<br/>      default_action             = string<br/>      bypass                     = optional(list(string), ["AzureServices"])<br/>      ip_rules                   = optional(list(string))<br/>      virtual_network_subnet_ids = optional(list(string))<br/>    }))<br/>    wire_host_storage_settings = optional(bool, true)<br/><br/>    # Identity.<br/>    create_user_assigned_identity = optional(bool, true)<br/>    identity = optional(object({<br/>      type         = string<br/>      identity_ids = optional(list(string))<br/>    }))<br/><br/>    # Observability. The grant flag exists because the AI id is usually a same-plan module output<br/>    # (unknown until apply), and for_each keys must stay plan-known: set it alongside<br/>    # app_insights_id to grant Monitoring Metrics Publisher to the module-created identity.<br/>    app_insights_connection_string       = optional(string)<br/>    app_insights_id                      = optional(string)<br/>    grant_app_insights_metrics_publisher = optional(bool, false)<br/><br/>    # Scale and runtime.<br/>    maximum_instance_count = optional(number)<br/>    instance_memory_in_mb  = optional(number, 2048)<br/>    http_concurrency       = optional(number)<br/>    always_ready = optional(list(object({<br/>      name           = string<br/>      instance_count = optional(number)<br/>    })), [])<br/><br/>    # Security and networking.<br/>    https_only                                     = optional(bool, true)<br/>    public_network_access_enabled                  = optional(bool, true)<br/>    virtual_network_subnet_id                      = optional(string)<br/>    client_certificate_enabled                     = optional(bool)<br/>    client_certificate_mode                        = optional(string)<br/>    client_certificate_exclusion_paths             = optional(string)<br/>    webdeploy_publish_basic_authentication_enabled = optional(bool)<br/>    enabled                                        = optional(bool, true)<br/><br/>    # Deployment. zip_deploy_file is broken upstream for flex (its publish poll 404s); the<br/>    # supported pattern is pushing the package with one-deploy from OUTSIDE the resource (see the<br/>    # complete example: archive_file + az functionapp deployment source config-zip keyed on the<br/>    # package hash). An ARM-native pull deploy is impossible keyless: one-deploy fetches<br/>    # packageUri anonymously (verified live), and keyless accounts cannot mint SAS.<br/>    zip_deploy_file = optional(string)<br/><br/>    # Settings.<br/>    app_settings = optional(map(string), {})<br/>    connection_strings = optional(list(object({<br/>      name  = string<br/>      type  = string<br/>      value = string<br/>    })), [])<br/>    sticky_settings = optional(object({<br/>      app_setting_names       = optional(list(string))<br/>      connection_string_names = optional(list(string))<br/>    }))<br/><br/>    site_config = optional(object({<br/>      api_definition_url                            = optional(string)<br/>      api_management_api_id                         = optional(string)<br/>      app_command_line                              = optional(string)<br/>      application_insights_connection_string        = optional(string)<br/>      application_insights_key                      = optional(string)<br/>      container_registry_managed_identity_client_id = optional(string)<br/>      container_registry_use_managed_identity       = optional(bool)<br/>      default_documents                             = optional(list(string))<br/>      elastic_instance_minimum                      = optional(number)<br/>      health_check_eviction_time_in_min             = optional(number)<br/>      health_check_path                             = optional(string)<br/>      http2_enabled                                 = optional(bool)<br/>      ip_restriction_default_action                 = optional(string)<br/>      load_balancing_mode                           = optional(string)<br/>      managed_pipeline_mode                         = optional(string)<br/>      minimum_tls_version                           = optional(string)<br/>      remote_debugging_enabled                      = optional(bool)<br/>      remote_debugging_version                      = optional(string)<br/>      runtime_scale_monitoring_enabled              = optional(bool)<br/>      scm_ip_restriction_default_action             = optional(string)<br/>      scm_minimum_tls_version                       = optional(string)<br/>      scm_use_main_ip_restriction                   = optional(bool)<br/>      use_32_bit_worker                             = optional(bool)<br/>      vnet_route_all_enabled                        = optional(bool)<br/>      websockets_enabled                            = optional(bool)<br/>      worker_count                                  = optional(number)<br/><br/>      app_service_logs = optional(object({<br/>        disk_quota_mb         = optional(number)<br/>        retention_period_days = optional(number)<br/>      }))<br/><br/>      cors = optional(object({<br/>        allowed_origins     = optional(list(string))<br/>        support_credentials = optional(bool)<br/>      }))<br/><br/>      ip_restrictions = optional(list(object({<br/>        action                    = optional(string)<br/>        description               = optional(string)<br/>        ip_address                = optional(string)<br/>        name                      = optional(string)<br/>        priority                  = optional(number)<br/>        service_tag               = optional(string)<br/>        virtual_network_subnet_id = optional(string)<br/>        headers = optional(list(object({<br/>          x_azure_fdid      = optional(list(string))<br/>          x_fd_health_probe = optional(list(string))<br/>          x_forwarded_for   = optional(list(string))<br/>          x_forwarded_host  = optional(list(string))<br/>        })))<br/>      })), [])<br/><br/>      scm_ip_restrictions = optional(list(object({<br/>        action                    = optional(string)<br/>        description               = optional(string)<br/>        ip_address                = optional(string)<br/>        name                      = optional(string)<br/>        priority                  = optional(number)<br/>        service_tag               = optional(string)<br/>        virtual_network_subnet_id = optional(string)<br/>        headers = optional(list(object({<br/>          x_azure_fdid      = optional(list(string))<br/>          x_fd_health_probe = optional(list(string))<br/>          x_forwarded_for   = optional(list(string))<br/>          x_forwarded_host  = optional(list(string))<br/>        })))<br/>      })), [])<br/>    }), {})<br/><br/>    auth_settings = optional(object({<br/>      enabled                        = bool<br/>      additional_login_parameters    = optional(map(string))<br/>      allowed_external_redirect_urls = optional(list(string))<br/>      default_provider               = optional(string)<br/>      issuer                         = optional(string)<br/>      runtime_version                = optional(string)<br/>      token_refresh_extension_hours  = optional(number)<br/>      token_store_enabled            = optional(bool)<br/>      unauthenticated_client_action  = optional(string)<br/><br/>      active_directory = optional(object({<br/>        client_id                  = string<br/>        allowed_audiences          = optional(list(string))<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>      }))<br/>      facebook = optional(object({<br/>        app_id                  = string<br/>        app_secret              = optional(string)<br/>        app_secret_setting_name = optional(string)<br/>        oauth_scopes            = optional(list(string))<br/>      }))<br/>      github = optional(object({<br/>        client_id                  = string<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>        oauth_scopes               = optional(list(string))<br/>      }))<br/>      google = optional(object({<br/>        client_id                  = string<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>        oauth_scopes               = optional(list(string))<br/>      }))<br/>      microsoft = optional(object({<br/>        client_id                  = string<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>        oauth_scopes               = optional(list(string))<br/>      }))<br/>      twitter = optional(object({<br/>        consumer_key                 = string<br/>        consumer_secret              = optional(string)<br/>        consumer_secret_setting_name = optional(string)<br/>      }))<br/>    }))<br/><br/>    auth_settings_v2 = optional(object({<br/>      auth_enabled                            = optional(bool)<br/>      config_file_path                        = optional(string)<br/>      default_provider                        = optional(string)<br/>      excluded_paths                          = optional(list(string))<br/>      forward_proxy_convention                = optional(string)<br/>      forward_proxy_custom_host_header_name   = optional(string)<br/>      forward_proxy_custom_scheme_header_name = optional(string)<br/>      http_route_api_prefix                   = optional(string)<br/>      require_authentication                  = optional(bool)<br/>      require_https                           = optional(bool)<br/>      runtime_version                         = optional(string)<br/>      unauthenticated_action                  = optional(string)<br/><br/>      active_directory_v2 = optional(object({<br/>        client_id                            = string<br/>        tenant_auth_endpoint                 = string<br/>        allowed_applications                 = optional(list(string))<br/>        allowed_audiences                    = optional(list(string))<br/>        allowed_groups                       = optional(list(string))<br/>        allowed_identities                   = optional(list(string))<br/>        client_secret_certificate_thumbprint = optional(string)<br/>        client_secret_setting_name           = optional(string)<br/>        jwt_allowed_client_applications      = optional(list(string))<br/>        jwt_allowed_groups                   = optional(list(string))<br/>        login_parameters                     = optional(map(string))<br/>        www_authentication_disabled          = optional(bool)<br/>      }))<br/>      apple_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>      }))<br/>      azure_static_web_app_v2 = optional(object({<br/>        client_id = string<br/>      }))<br/>      custom_oidc_v2 = optional(list(object({<br/>        client_id                     = string<br/>        name                          = string<br/>        openid_configuration_endpoint = string<br/>        name_claim_type               = optional(string)<br/>        scopes                        = optional(list(string))<br/>      })), [])<br/>      facebook_v2 = optional(object({<br/>        app_id                  = string<br/>        app_secret_setting_name = string<br/>        graph_api_version       = optional(string)<br/>        login_scopes            = optional(list(string))<br/>      }))<br/>      github_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      google_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        allowed_audiences          = optional(list(string))<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      microsoft_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        allowed_audiences          = optional(list(string))<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      twitter_v2 = optional(object({<br/>        consumer_key                 = string<br/>        consumer_secret_setting_name = string<br/>      }))<br/>      login = optional(object({<br/>        allowed_external_redirect_urls    = optional(list(string))<br/>        cookie_expiration_convention      = optional(string)<br/>        cookie_expiration_time            = optional(string)<br/>        logout_endpoint                   = optional(string)<br/>        nonce_expiration_time             = optional(string)<br/>        preserve_url_fragments_for_logins = optional(bool)<br/>        token_refresh_extension_time      = optional(number)<br/>        token_store_enabled               = optional(bool)<br/>        token_store_path                  = optional(string)<br/>        token_store_sas_setting_name      = optional(string)<br/>        validate_nonce                    = optional(bool)<br/>      }), {})<br/>    }))<br/><br/>    tags = optional(map(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | The Azure region the plans, apps, and created storage live in. | `string` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | The id of the resource group everything lands in. Parsed for the resource group name. | `string` | n/a | yes |
| <a name="input_service_plans"></a> [service\_plans](#input\_service\_plans) | Service plans the module creates, keyed by name. Multiple function apps can share one plan by<br/>referencing its key, even though flex consumption is commonly one app per plan today. sku\_name is<br/>not welded to FC1 and app\_service\_environment\_id allows App Service Environment placement, so the<br/>map stays general purpose. Apps that reference no plan at all get a dedicated FC1 plan named<br/>asp-<app key> automatically (one module call = running app). | <pre>map(object({<br/>    os_type                    = optional(string, "Linux")<br/>    sku_name                   = optional(string, "FC1")<br/>    app_service_environment_id = optional(string)<br/>    zone_balancing_enabled     = optional(bool)<br/>    worker_count               = optional(number)<br/>    tags                       = optional(map(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to everything the module creates (merged with any per-item tags). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_default_hostnames"></a> [default\_hostnames](#output\_default\_hostnames) | Map of app name to its default hostname (https://<hostname> is the app's base URL). |
| <a name="output_function_app_ids"></a> [function\_app\_ids](#output\_function\_app\_ids) | Map of app name to its id. |
| <a name="output_function_app_ids_zipmap"></a> [function\_app\_ids\_zipmap](#output\_function\_app\_ids\_zipmap) | Map of app name to { name, id }, for easy composition with other modules. |
| <a name="output_function_apps"></a> [function\_apps](#output\_function\_apps) | Map of app name to the full flex consumption app object. Sensitive as a whole because the object carries storage\_access\_key and the site credentials; the ids, hostnames, and identity maps below stay plain for composition. |
| <a name="output_identity_principal_ids"></a> [identity\_principal\_ids](#output\_identity\_principal\_ids) | Map of app name to { system\_assigned, user\_assigned } principal ids (nulls where an identity kind is absent). |
| <a name="output_possible_outbound_ip_address_lists"></a> [possible\_outbound\_ip\_address\_lists](#output\_possible\_outbound\_ip\_address\_lists) | Map of app name to the app's possible outbound IPs: the allow-list for locking the backing storage down after create (see the complete example). |
| <a name="output_service_plan_ids"></a> [service\_plan\_ids](#output\_service\_plan\_ids) | Map of plan key (from service\_plans plus the dedicated asp-<app> plans) to its id. |
| <a name="output_storage_account_ids"></a> [storage\_account\_ids](#output\_storage\_account\_ids) | Map of app name to the created storage account id (only apps with created storage). |
| <a name="output_storage_container_endpoints"></a> [storage\_container\_endpoints](#output\_storage\_container\_endpoints) | Map of app name to the deployment container endpoint the app runs from. |
| <a name="output_user_assigned_identity_ids"></a> [user\_assigned\_identity\_ids](#output\_user\_assigned\_identity\_ids) | Map of app name to the module-created user assigned identity id (only apps with create\_user\_assigned\_identity). |
<!-- END_TF_DOCS -->
