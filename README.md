```hcl
################################################
#  Service Plan (only when caller requests one)
################################################
resource "azurerm_service_plan" "service_plan" {
  for_each            = { for app in var.flex_function_apps : app.name => app if app.create_new_app_service_plan == true }
  name                = each.value.app_service_plan_name != null ? each.value.app_service_plan_name : "asp-${each.value.name}"
  resource_group_name = each.value.rg_name
  location            = each.value.location
  os_type             = each.value.os_type != null ? title(each.value.os_type) : "Linux"
  sku_name            = each.value.sku_name
}

################################################
#  Flex Function App(s)
################################################
resource "azurerm_function_app_flex_consumption" "function_app" {
  for_each = { for app in var.flex_function_apps : app.name => app }

  name                = each.value.name
  service_plan_id     = each.value.service_plan_id != null ? each.value.service_plan_id : lookup(azurerm_service_plan.service_plan, each.key, null).id
  location            = each.value.location
  resource_group_name = each.value.rg_name

  # ── Flex‑specific mandatory fields ─────────────────────────────
  runtime_name                      = lower(each.value.runtime_name)
  runtime_version                   = lower(each.value.runtime_version)
  storage_container_type            = coalesce(each.value.storage_container_type, "blobContainer")
  storage_container_endpoint        = each.value.storage_container_endpoint
  storage_authentication_type       = lower(each.value.identity_type) == "systemassigned" ? "SystemAssignedIdentity" : lower(each.value.identity_type) == "userassigned" && each.value.identity_ids != [] ? "UserAssignedIdentity" : each.value.storage_authentication_type
  storage_access_key                = each.value.storage_authentication_type == "StorageAccountConnectionString" ? each.value.storage_access_key : null
  storage_user_assigned_identity_id = lower(each.value.identity_type) == "userassigned" && each.value.identity_ids != [] ? each.value.identity_ids[0] : each.value.storage_user_assigned_identity_id

  maximum_instance_count = each.value.maximum_instance_count
  instance_memory_in_mb  = each.value.instance_memory_in_mb

  # ── Classic settings (kept from original style) ────────────────
  app_settings                                   = each.value.create_new_app_insights == true && lookup(local.app_insights_map, each.value.app_insights_name, null) != null ? merge(each.value.app_settings, local.app_insights_map[each.value.app_insights_name]) : each.value.app_settings
  tags                                           = each.value.tags
  client_certificate_enabled                     = each.value.client_certificate_enabled
  client_certificate_mode                        = each.value.client_certificate_mode
  client_certificate_exclusion_paths             = each.value.client_certificate_exclusion_paths
  enabled                                        = each.value.enabled
  public_network_access_enabled                  = each.value.public_network_access_enabled
  virtual_network_subnet_id                      = each.value.virtual_network_subnet_id
  webdeploy_publish_basic_authentication_enabled = each.value.webdeploy_publish_basic_authentication_enabled
  zip_deploy_file                                = each.value.zip_deploy_file

  # ── Identity blocks ────────────────────────────────────────────
  dynamic "identity" {
    for_each = each.value.identity_type == "SystemAssigned" ? ["SA"] : []
    content {
      type = "SystemAssigned"
    }
  }

  dynamic "identity" {
    for_each = each.value.identity_type == "SystemAssigned, UserAssigned" ? ["SAUA"] : []
    content {
      type         = "SystemAssigned, UserAssigned"
      identity_ids = try(each.value.identity_ids, [])
    }
  }

  dynamic "identity" {
    for_each = each.value.identity_type == "UserAssigned" ? ["UA"] : []
    content {
      type         = "UserAssigned"
      identity_ids = length(try(each.value.identity_ids, [])) > 0 ? each.value.identity_ids : []
    }
  }


  dynamic "sticky_settings" {
    for_each = each.value.sticky_settings != null ? [each.value.sticky_settings] : []
    content {
      app_setting_names       = sticky_settings.value.app_setting_names
      connection_string_names = sticky_settings.value.connection_string_names
    }
  }

  dynamic "connection_string" {
    for_each = each.value.connection_string != null ? [each.value.connection_string] : []
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  dynamic "auth_settings" {
    for_each = each.value.auth_settings != null ? [each.value.auth_settings] : []

    content {
      enabled                        = auth_settings.value.enabled
      additional_login_parameters    = auth_settings.value.additional_login_parameters
      allowed_external_redirect_urls = auth_settings.value.allowed_external_redirect_urls
      default_provider               = auth_settings.value.default_provider
      issuer                         = auth_settings.value.issuer
      runtime_version                = auth_settings.value.runtime_version
      token_refresh_extension_hours  = auth_settings.value.token_refresh_extension_hours
      token_store_enabled            = auth_settings.value.token_store_enabled
      unauthenticated_client_action  = auth_settings.value.unauthenticated_client_action

      dynamic "active_directory" {
        for_each = auth_settings.value.active_directory != null ? [auth_settings.value.active_directory] : []

        content {
          client_id         = active_directory.value.client_id
          client_secret     = active_directory.value.client_secret
          allowed_audiences = active_directory.value.allowed_audiences
        }
      }

      dynamic "facebook" {
        for_each = auth_settings.value.facebook != null ? [auth_settings.value.facebook] : []

        content {
          app_id       = facebook.value.app_id
          app_secret   = facebook.value.app_secret
          oauth_scopes = facebook.value.oauth_scopes
        }
      }

      dynamic "google" {
        for_each = auth_settings.value.google != null ? [auth_settings.value.google] : []

        content {
          client_id     = google.value.client_id
          client_secret = google.value.client_secret
          oauth_scopes  = google.value.oauth_scopes
        }
      }

      dynamic "microsoft" {
        for_each = auth_settings.value.microsoft != null ? [auth_settings.value.microsoft] : []

        content {
          client_id     = microsoft.value.client_id
          client_secret = microsoft.value.client_secret
          oauth_scopes  = microsoft.value.oauth_scopes
        }
      }

      dynamic "twitter" {
        for_each = auth_settings.value.twitter != null ? [auth_settings.value.twitter] : []

        content {
          consumer_key    = twitter.value.consumer_key
          consumer_secret = twitter.value.consumer_secret
        }
      }

      dynamic "github" {
        for_each = auth_settings.value.github != null ? [auth_settings.value.github] : []

        content {
          client_id                  = github.value.client_id
          client_secret              = github.value.client_secret
          client_secret_setting_name = github.value.client_secret_setting_name
          oauth_scopes               = github.value.oauth_scopes
        }
      }
    }
  }

  dynamic "auth_settings_v2" {
    for_each = each.value.auth_settings_v2 != null ? [each.value.auth_settings_v2] : []

    content {
      auth_enabled                            = auth_settings_v2.value.auth_enabled
      runtime_version                         = auth_settings_v2.value.runtime_version
      config_file_path                        = auth_settings_v2.value.config_file_path
      require_authentication                  = auth_settings_v2.value.require_authentication
      unauthenticated_action                  = auth_settings_v2.value.unauthenticated_action
      default_provider                        = auth_settings_v2.value.default_provider
      excluded_paths                          = toset(auth_settings_v2.value.excluded_paths)
      require_https                           = auth_settings_v2.value.require_https
      http_route_api_prefix                   = auth_settings_v2.value.http_route_api_prefix
      forward_proxy_convention                = auth_settings_v2.value.forward_proxy_convention
      forward_proxy_custom_host_header_name   = auth_settings_v2.value.forward_proxy_custom_host_header_name
      forward_proxy_custom_scheme_header_name = auth_settings_v2.value.forward_proxy_custom_scheme_header_name

      dynamic "apple_v2" {
        for_each = auth_settings_v2.value.apple_v2 != null ? [auth_settings_v2.value.apple_v2] : []

        content {
          client_id                  = apple_v2.value.client_id
          client_secret_setting_name = apple_v2.value.client_secret_setting_name
          login_scopes               = toset(apple_v2.value.login_scopes)
        }
      }

      dynamic "active_directory_v2" {
        for_each = auth_settings_v2.value.active_directory_v2 != null ? [auth_settings_v2.value.active_directory_v2] : []

        content {
          client_id                            = active_directory_v2.value.client_id
          tenant_auth_endpoint                 = active_directory_v2.value.tenant_auth_endpoint
          client_secret_setting_name           = active_directory_v2.value.client_secret_setting_name
          client_secret_certificate_thumbprint = active_directory_v2.value.client_secret_certificate_thumbprint
          jwt_allowed_groups                   = toset(active_directory_v2.value.jwt_allowed_groups)
          jwt_allowed_client_applications      = toset(active_directory_v2.value.jwt_allowed_client_applications)
          www_authentication_disabled          = active_directory_v2.value.www_authentication_disabled
          allowed_groups                       = toset(active_directory_v2.value.allowed_groups)
          allowed_identities                   = toset(active_directory_v2.value.allowed_identities)
          allowed_applications                 = toset(active_directory_v2.value.allowed_applications)
          login_parameters                     = active_directory_v2.value.login_parameters
          allowed_audiences                    = toset(active_directory_v2.value.allowed_audiences)
        }
      }

      dynamic "azure_static_web_app_v2" {
        for_each = auth_settings_v2.value.azure_static_web_app_v2 != null ? [auth_settings_v2.value.azure_static_web_app_v2] : []

        content {
          client_id = azure_static_web_app_v2.value.client_id
        }
      }

      dynamic "custom_oidc_v2" {
        for_each = auth_settings_v2.value.custom_oidc_v2 != null ? [auth_settings_v2.value.custom_oidc_v2] : []

        content {
          name                          = custom_oidc_v2.value.name
          client_id                     = custom_oidc_v2.value.client_id
          openid_configuration_endpoint = custom_oidc_v2.value.openid_configuration_endpoint
          name_claim_type               = custom_oidc_v2.value.name_claim_type
          scopes                        = toset(custom_oidc_v2.value.scopes)
          client_credential_method      = custom_oidc_v2.value.client_credential_method
          client_secret_setting_name    = custom_oidc_v2.value.client_secret_setting_name
          authorisation_endpoint        = custom_oidc_v2.value.authorisation_endpoint
          token_endpoint                = custom_oidc_v2.value.token_endpoint
          issuer_endpoint               = custom_oidc_v2.value.issuer_endpoint
          certification_uri             = custom_oidc_v2.value.certification_uri
        }
      }


      dynamic "facebook_v2" {
        for_each = auth_settings_v2.value.facebook_v2 != null ? [auth_settings_v2.value.facebook_v2] : []

        content {
          graph_api_version       = facebook_v2.value.graph_api_version
          login_scopes            = toset(facebook_v2.value.login_scopes)
          app_id                  = facebook_v2_value.app_id
          app_secret_setting_name = facebook_v2.value.app_secret_setting_name
        }
      }

      dynamic "github_v2" {
        for_each = auth_settings_v2.value.github_v2 != null ? [auth_settings_v2.value.github_v2] : []

        content {
          client_id                  = github_v2.value.client_id
          client_secret_setting_name = github_v2.value.client_secret_setting_name
          login_scopes               = toset(github_v2.value.login_scopes)
        }
      }

      dynamic "google_v2" {
        for_each = auth_settings_v2.value.google_v2 != null ? [auth_settings_v2.value.google_v2] : []

        content {
          client_id                  = google_v2.value.client_id
          client_secret_setting_name = google_v2.value.client_secret_setting_name
          allowed_audiences          = toset(google_v2.value.allowed_audiences)
          login_scopes               = toset(google_v2.value.login_scopes)
        }
      }

      dynamic "microsoft_v2" {
        for_each = auth_settings_v2.value.microsoft_v2 != null ? [auth_settings_v2.value.microsoft_v2] : []

        content {
          client_id                  = microsoft_v2.value.client_id
          client_secret_setting_name = microsoft_v2.value.client_secret_setting_name
          allowed_audiences          = toset(microsoft_v2.value.allowed_audiences)
          login_scopes               = toset(microsoft_v2.value.login_scopes)
        }
      }

      dynamic "twitter_v2" {
        for_each = auth_settings_v2.value.twitter_v2 != null ? [auth_settings_v2.value.twitter_v2] : []
        content {
          consumer_key                 = twitter_v2.value.consumer_key
          consumer_secret_setting_name = twitter_v2.value.consumer_secret_setting_name
        }
      }

      dynamic "login" {
        for_each = auth_settings_v2.value.login != null ? [auth_settings_v2.value.login] : []

        content {
          logout_endpoint                   = login.value.logout_endpoint
          token_store_enabled               = login.value.token_store_enabled
          token_refresh_extension_time      = login.value.token_refresh_extension_time
          token_store_path                  = login.value.token_store_path
          token_store_sas_setting_name      = login.value.token_store_sas_setting_name
          preserve_url_fragments_for_logins = login.value.preserve_url_fragments_for_logins
          allowed_external_redirect_urls    = toset(login.value.allowed_external_redirect_urls)
          cookie_expiration_convention      = login.value.cookie_expiration_convention
          cookie_expiration_time            = login.value.cookie_expiration_time
          validate_nonce                    = login.value.validate_nonce
          nonce_expiration_time             = login.value.nonce_expiration_time
        }
      }
    }
  }


  dynamic "site_config" {
    for_each = each.value.site_config != null ? [each.value.site_config] : []

    content {
      api_definition_url                            = site_config.value.api_definition_url
      api_management_api_id                         = site_config.value.api_management_api_id
      app_command_line                              = site_config.value.app_command_line
      application_insights_connection_string        = site_config.value.application_insights_connection_string
      application_insights_key                      = site_config.value.application_insights_key
      container_registry_managed_identity_client_id = site_config.value.container_registry_managed_identity_client_id
      container_registry_use_managed_identity       = site_config.value.container_registry_use_managed_identity
      elastic_instance_minimum                      = site_config.value.elastic_instance_minimum
      health_check_path                             = site_config.value.health_check_path
      health_check_eviction_time_in_min             = site_config.value.health_check_eviction_time_in_min
      http2_enabled                                 = site_config.value.http2_enabled
      load_balancing_mode                           = site_config.value.load_balancing_mode
      managed_pipeline_mode                         = site_config.value.managed_pipeline_mode
      minimum_tls_version                           = site_config.value.minimum_tls_version
      remote_debugging_enabled                      = site_config.value.remote_debugging_enabled
      remote_debugging_version                      = site_config.value.remote_debugging_version
      runtime_scale_monitoring_enabled              = site_config.value.runtime_scale_monitoring_enabled
      scm_minimum_tls_version                       = site_config.value.scm_minimum_tls_version
      scm_use_main_ip_restriction                   = site_config.value.scm_use_main_ip_restriction
      use_32_bit_worker                             = site_config.value.use_32_bit_worker
      websockets_enabled                            = site_config.value.websockets_enabled
      worker_count                                  = site_config.value.worker_count
      default_documents                             = toset(site_config.value.default_documents)

      dynamic "app_service_logs" {
        for_each = site_config.value.app_service_logs != null ? [site_config.value.app_service_logs] : []
        content {
          disk_quota_mb         = app_service_logs.value.disk_quota_mb
          retention_period_days = app_service_logs.value.retention_period_days
        }
      }

      dynamic "cors" {
        for_each = site_config.value.cors != null ? [site_config.value.cors] : []
        content {
          allowed_origins     = cors.value.allowed_origins
          support_credentials = cors.value.support_credentials
        }
      }

      dynamic "ip_restriction" {
        for_each = site_config.value.ip_restriction != null ? site_config.value.ip_restriction : []

        content {
          ip_address                = ip_restriction.value.ip_address
          service_tag               = ip_restriction.value.service_tag
          virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
          name                      = ip_restriction.value.name
          priority                  = ip_restriction.value.priority
          action                    = ip_restriction.value.action

          dynamic "headers" {
            for_each = ip_restriction.value.headers != null ? [ip_restriction.value.headers] : []

            content {
              x_azure_fdid      = headers.value.x_azure_fdid
              x_fd_health_probe = headers.value.x_fd_health_prob
              x_forwarded_for   = headers.value.x_forwarded_for
              x_forwarded_host  = headers.value.x_forwarded_host
            }
          }
        }
      }

      dynamic "scm_ip_restriction" {
        for_each = site_config.value.scm_ip_restriction != null ? site_config.value.scm_ip_restriction : []

        content {
          ip_address                = scm_ip_restriction.value.ip_address
          service_tag               = scm_ip_restriction.value.service_tag
          virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id
          name                      = scm_ip_restriction.value.name
          priority                  = scm_ip_restriction.value.priority
          action                    = scm_ip_restriction.value.action

          dynamic "headers" {
            for_each = scm_ip_restriction.value.headers != null ? [scm_ip_restriction.value.headers] : []

            content {
              x_azure_fdid      = headers.value.x_azure_fdid
              x_fd_health_probe = headers.value.x_fd_health_prob
              x_forwarded_for   = headers.value.x_forwarded_for
              x_forwarded_host  = headers.value.x_forwarded_host
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      tags["hidden-link: /app-insights-conn-string"],
      tags["hidden-link: /app-insights-instrumentation-key"],
      tags["hidden-link: /app-insights-resource-id"],
    ]
  }
}
```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_application_insights.app_insights_workspace](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights) | resource |
| [azurerm_function_app_flex_consumption.function_app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/function_app_flex_consumption) | resource |
| [azurerm_service_plan.service_plan](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_flex_function_apps"></a> [flex\_function\_apps](#input\_flex\_function\_apps) | List of FlexΓÇæConsumption Function Apps (keeps original style) | <pre>list(object({<br/>    # ΓöÇΓöÇ Core identity ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ<br/>    name     = string<br/>    rg_name  = string<br/>    location = string<br/><br/>    # ΓöÇΓöÇ Plan creation ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ<br/>    create_new_app_service_plan = optional(bool, true)<br/>    app_service_plan_name       = optional(string)<br/>    service_plan_id             = optional(string)<br/>    os_type                     = optional(string, "Linux")<br/>    sku_name                    = optional(string, "FC1")<br/><br/>    # ΓöÇΓöÇ FlexΓÇæspecific mandatory fields ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ<br/>    runtime_name                      = string # "dotnet-isolated" | "python" | "node" | "java"<br/>    runtime_version                   = string # e.g. "8.0", "3.11"<br/>    storage_container_type            = optional(string, "blobContainer")<br/>    storage_user_assigned_identity_id = optional(string)<br/>    storage_container_endpoint        = string                                     # "https://<account>.blob.core.windows.net/<container>"<br/>    storage_authentication_type       = optional(string, "SystemAssignedIdentity") # or "StorageAccountConnectionString"<br/>    storage_access_key                = optional(string)                           # only when auth type is connection string<br/>    maximum_instance_count            = optional(number)                           # default from portal (100) if omitted<br/>    instance_memory_in_mb             = optional(number, 2048)                     # must be 2048 or 4096<br/><br/>    app_settings                                   = map(string)<br/>    tags                                           = optional(map(string))<br/>    client_certificate_enabled                     = optional(bool)<br/>    client_certificate_exclusion_paths             = optional(string)<br/>    client_certificate_mode                        = optional(string)<br/>    enabled                                        = optional(bool, true)<br/>    content_share_force_disabled                   = optional(bool)<br/>    identity_type                                  = optional(string)<br/>    public_network_access_enabled                  = optional(bool, true)<br/>    virtual_network_subnet_id                      = optional(string)<br/>    webdeploy_publish_basic_authentication_enabled = optional(bool, false)<br/>    zip_deploy_file                                = optional(string)<br/><br/>    identity_ids = optional(list(string))<br/><br/>    # ΓöÇΓöÇ Application Insights options (unchanged) ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ<br/>    create_new_app_insights                            = optional(bool, false)<br/>    workspace_id                                       = optional(string)<br/>    app_insights_name                                  = optional(string)<br/>    app_insights_type                                  = optional(string, "Web")<br/>    app_insights_daily_cap_in_gb                       = optional(number)<br/>    app_insights_daily_data_cap_notifications_disabled = optional(bool, false)<br/>    app_insights_internet_ingestion_enabled            = optional(bool)<br/>    app_insights_internet_query_enabled                = optional(bool)<br/>    app_insights_local_authentication_disabled         = optional(bool, true)<br/>    app_insights_force_customer_storage_for_profile    = optional(bool, false)<br/>    app_insights_sampling_percentage                   = optional(number, 100)<br/><br/>    sticky_settings = optional(object({<br/>      app_setting_names       = optional(list(string))<br/>      connection_string_names = optional(list(string))<br/>    }))<br/><br/>    connection_string = optional(object({<br/>      name  = optional(string)<br/>      type  = optional(string)<br/>      value = optional(string)<br/>    }))<br/>    auth_settings_v2 = optional(object({<br/>      auth_enabled                            = optional(bool)<br/>      runtime_version                         = optional(string)<br/>      config_file_path                        = optional(string)<br/>      require_authentication                  = optional(bool)<br/>      unauthenticated_action                  = optional(string)<br/>      default_provider                        = optional(string)<br/>      excluded_paths                          = optional(list(string))<br/>      require_https                           = optional(bool)<br/>      http_route_api_prefix                   = optional(string)<br/>      forward_proxy_convention                = optional(string)<br/>      forward_proxy_custom_host_header_name   = optional(string)<br/>      forward_proxy_custom_scheme_header_name = optional(string)<br/>      apple_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        login_scopes               = list(string)<br/>      }))<br/>      active_directory_v2 = optional(object({<br/>        client_id                            = string<br/>        tenant_auth_endpoint                 = string<br/>        client_secret_setting_name           = optional(string)<br/>        client_secret_certificate_thumbprint = optional(string)<br/>        jwt_allowed_groups                   = optional(list(string))<br/>        jwt_allowed_client_applications      = optional(list(string))<br/>        www_authentication_disabled          = optional(bool)<br/>        allowed_groups                       = optional(list(string))<br/>        allowed_identities                   = optional(list(string))<br/>        allowed_applications                 = optional(list(string))<br/>        login_parameters                     = optional(map(string))<br/>        allowed_audiences                    = optional(list(string))<br/>      }))<br/>      azure_static_web_app_v2 = optional(object({<br/>        client_id = string<br/>      }))<br/>      custom_oidc_v2 = optional(list(object({<br/>        name                          = string<br/>        client_id                     = string<br/>        openid_configuration_endpoint = string<br/>        name_claim_type               = optional(string)<br/>        scopes                        = optional(list(string))<br/>        client_credential_method      = string<br/>        client_secret_setting_name    = string<br/>        authorisation_endpoint        = string<br/>        token_endpoint                = string<br/>        issuer_endpoint               = string<br/>        certification_uri             = string<br/>      })))<br/>      facebook_v2 = optional(object({<br/>        app_id                  = string<br/>        app_secret_setting_name = string<br/>        graph_api_version       = optional(string)<br/>        login_scopes            = optional(list(string))<br/>      }))<br/>      github_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      google_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        allowed_audiences          = optional(list(string))<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      microsoft_v2 = optional(object({<br/>        client_id                  = string<br/>        client_secret_setting_name = string<br/>        allowed_audiences          = optional(list(string))<br/>        login_scopes               = optional(list(string))<br/>      }))<br/>      twitter_v2 = optional(object({<br/>        consumer_key                 = string<br/>        consumer_secret_setting_name = string<br/>      }))<br/>      login = optional(object({<br/>        logout_endpoint                   = optional(string)<br/>        token_store_enabled               = optional(bool)<br/>        token_refresh_extension_time      = optional(number)<br/>        token_store_path                  = optional(string)<br/>        token_store_sas_setting_name      = optional(string)<br/>        preserve_url_fragments_for_logins = optional(bool)<br/>        allowed_external_redirect_urls    = optional(list(string))<br/>        cookie_expiration_convention      = optional(string)<br/>        cookie_expiration_time            = optional(string)<br/>        validate_nonce                    = optional(bool)<br/>        nonce_expiration_time             = optional(string)<br/>      }))<br/>    }))<br/>    auth_settings = optional(object({<br/>      enabled                        = optional(bool)<br/>      additional_login_parameters    = optional(map(string))<br/>      allowed_external_redirect_urls = optional(list(string))<br/>      default_provider               = optional(string)<br/>      issuer                         = optional(string)<br/>      runtime_version                = optional(string)<br/>      token_refresh_extension_hours  = optional(number)<br/>      token_store_enabled            = optional(bool)<br/>      unauthenticated_client_action  = optional(string)<br/>      active_directory = optional(object({<br/>        client_id         = optional(string)<br/>        client_secret     = optional(string)<br/>        allowed_audiences = optional(list(string))<br/>      }))<br/>      facebook = optional(object({<br/>        app_id       = optional(string)<br/>        app_secret   = optional(string)<br/>        oauth_scopes = optional(list(string))<br/>      }))<br/>      google = optional(object({<br/>        client_id     = optional(string)<br/>        client_secret = optional(string)<br/>        oauth_scopes  = optional(list(string))<br/>      }))<br/>      microsoft = optional(object({<br/>        client_id     = optional(string)<br/>        client_secret = optional(string)<br/>        oauth_scopes  = optional(list(string))<br/>      }))<br/>      twitter = optional(object({<br/>        consumer_key    = optional(string)<br/>        consumer_secret = optional(string)<br/>      }))<br/>      github = optional(object({<br/>        client_id                  = optional(string)<br/>        client_secret              = optional(string)<br/>        client_secret_setting_name = optional(string)<br/>        oauth_scopes               = optional(list(string))<br/>      }))<br/>    }))<br/>    site_config = optional(object({<br/>      api_definition_url                            = optional(string)<br/>      api_management_api_id                         = optional(string)<br/>      app_command_line                              = optional(string)<br/>      application_insights_connection_string        = optional(string)<br/>      application_insights_key                      = optional(string)<br/>      container_registry_managed_identity_client_id = optional(string)<br/>      container_registry_use_managed_identity       = optional(bool)<br/>      elastic_instance_minimum                      = optional(number)<br/>      health_check_path                             = optional(string)<br/>      health_check_eviction_time_in_min             = optional(number)<br/>      http2_enabled                                 = optional(bool)<br/>      load_balancing_mode                           = optional(string)<br/>      managed_pipeline_mode                         = optional(string)<br/>      minimum_tls_version                           = optional(string)<br/>      remote_debugging_enabled                      = optional(bool)<br/>      remote_debugging_version                      = optional(string)<br/>      runtime_scale_monitoring_enabled              = optional(bool)<br/>      scm_minimum_tls_version                       = optional(string)<br/>      scm_use_main_ip_restriction                   = optional(bool)<br/>      use_32_bit_worker                             = optional(bool)<br/>      websockets_enabled                            = optional(bool)<br/>      worker_count                                  = optional(number)<br/>      default_documents                             = optional(list(string))<br/>      app_service_logs = optional(object({<br/>        disk_quota_mb         = optional(number)<br/>        retention_period_days = optional(number)<br/>      }))<br/>      cors = optional(object({<br/>        allowed_origins     = optional(list(string))<br/>        support_credentials = optional(bool)<br/>      }))<br/>      ip_restriction = optional(list(object({<br/>        ip_address                = optional(string)<br/>        service_tag               = optional(string)<br/>        virtual_network_subnet_id = optional(string)<br/>        name                      = optional(string)<br/>        priority                  = optional(number)<br/>        action                    = optional(string)<br/>        headers = optional(object({<br/>          x_azure_fdid      = optional(string)<br/>          x_fd_health_probe = optional(string)<br/>          x_forwarded_for   = optional(string)<br/>          x_forwarded_host  = optional(string)<br/>        }))<br/>      })))<br/>      scm_ip_restriction = optional(list(object({<br/>        ip_address                = optional(string)<br/>        service_tag               = optional(string)<br/>        virtual_network_subnet_id = optional(string)<br/>        name                      = optional(string)<br/>        priority                  = optional(number)<br/>        action                    = optional(string)<br/>        headers = optional(object({<br/>          x_azure_fdid      = optional(string)<br/>          x_fd_health_probe = optional(string)<br/>          x_forwarded_for   = optional(string)<br/>          x_forwarded_host  = optional(string)<br/>        }))<br/>      })))<br/>    }))<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_function_app_identities"></a> [function\_app\_identities](#output\_function\_app\_identities) | The identities of the Storage Accounts. |
| <a name="output_function_app_names"></a> [function\_app\_names](#output\_function\_app\_names) | The default name of the Linux Function Apps. |
| <a name="output_function_apps_custom_domain_verification_id"></a> [function\_apps\_custom\_domain\_verification\_id](#output\_function\_apps\_custom\_domain\_verification\_id) | The custom domain verification IDs of the Linux Function Apps. |
| <a name="output_function_apps_default_hostnames"></a> [function\_apps\_default\_hostnames](#output\_function\_apps\_default\_hostnames) | The default hostnames of the Linux Function Apps. |
| <a name="output_function_apps_outbound_ip_addresses"></a> [function\_apps\_outbound\_ip\_addresses](#output\_function\_apps\_outbound\_ip\_addresses) | The outbound IP addresses of the Linux Function Apps. |
| <a name="output_function_apps_possible_outbound_ip_addresses"></a> [function\_apps\_possible\_outbound\_ip\_addresses](#output\_function\_apps\_possible\_outbound\_ip\_addresses) | The possible outbound IP addresses of the Linux Function Apps. |
| <a name="output_function_apps_site_credentials"></a> [function\_apps\_site\_credentials](#output\_function\_apps\_site\_credentials) | The site credentials for the Linux Function Apps. |
| <a name="output_linux_function_apps_ids"></a> [linux\_function\_apps\_ids](#output\_linux\_function\_apps\_ids) | The IDs of the Linux Function Apps. |
| <a name="output_service_plans_ids"></a> [service\_plans\_ids](#output\_service\_plans\_ids) | The IDs of the Service Plans. |
