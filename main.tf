locals {
  rg = provider::azurerm::parse_resource_id(var.resource_group_id)

  # Apps that reference no plan get a dedicated FC1 plan (asp-<app key>).
  auto_plan_apps = { for k, a in var.function_apps : k => a if a.service_plan_key == null && a.service_plan_id == null }

  # Storage shape per app.
  storage_create_apps = { for k, a in var.function_apps : k => a if a.create_storage_account }
  storage_byo_apps    = { for k, a in var.function_apps : k => a if a.storage_account_id != null }

  # A storage account name must be 3-24 lower alphanumerics and globally unique; the derived
  # default flattens the app key. Callers override storage_account_name when it collides.
  storage_account_names = {
    for k, a in local.storage_create_apps : k => coalesce(a.storage_account_name, substr(replace(replace(lower("st${k}"), "-", ""), "_", ""), 0, 24))
  }

  # The identity the app runs and authenticates to storage with: module-created UAI by default
  # (system-assigned plus deploy-during-create is a bootstrap deadlock), or caller-supplied.
  uai_apps = { for k, a in var.function_apps : k => a if a.create_user_assigned_identity }

  identity_blocks = {
    for k, a in var.function_apps : k => (
      a.identity != null ? a.identity : {
        type         = "SystemAssigned, UserAssigned"
        identity_ids = [azurerm_user_assigned_identity.this[k].id]
      }
    )
  }

  # Storage auth derivation: explicit wins; else UAI when one is wired, else system-assigned.
  storage_auth = {
    for k, a in var.function_apps : k => coalesce(
      a.storage_authentication_type,
      a.create_user_assigned_identity || try(a.identity.identity_ids, null) != null ? "UserAssignedIdentity" : "SystemAssignedIdentity"
    )
  }

  storage_uai_id = {
    for k, a in var.function_apps : k => (
      local.storage_auth[k] != "UserAssignedIdentity" ? null :
      a.create_user_assigned_identity ? azurerm_user_assigned_identity.this[k].id : try(a.identity.identity_ids[0], null)
    )
  }

  # The deployment container endpoint per storage shape.
  storage_container_endpoints = {
    for k, a in var.function_apps : k => (
      a.storage_container_endpoint != null ? a.storage_container_endpoint :
      a.create_storage_account ? "${azurerm_storage_account.this[k].primary_blob_endpoint}${azurerm_storage_container.this[k].name}" :
      "https://${provider::azurerm::parse_resource_id(a.storage_account_id).resource_name}.blob.core.windows.net/${a.storage_container_name}"
    )
  }

  # Grants happen wherever the module has a scope AND owns the identity: created or BYO-by-id
  # storage with a module-created UAI. The raw endpoint shape and caller identities grant nothing.
  storage_grant_scopes = {
    for k, a in var.function_apps : k => (
      a.create_storage_account ? azurerm_storage_account.this[k].id : a.storage_account_id
    ) if a.create_user_assigned_identity && a.storage_container_endpoint == null
  }

  storage_grants = merge([
    for k, scope in local.storage_grant_scopes : {
      for role in var.function_apps[k].storage_role_names : "${k}|${role}" => {
        app   = k
        scope = scope
        role  = role
      }
    }
  ]...)

  # The documented keyless recipe: identity-based host storage app settings, wired whenever the
  # app authenticates to storage with an identity (opt out via wire_host_storage_settings).
  host_storage_settings = {
    for k, a in var.function_apps : k => (
      a.wire_host_storage_settings && local.storage_auth[k] != "StorageAccountConnectionString" && a.storage_container_endpoint == null ? {
        AzureWebJobsStorage__accountName = a.create_storage_account ? azurerm_storage_account.this[k].name : provider::azurerm::parse_resource_id(a.storage_account_id).resource_name
        AzureWebJobsStorage__credential  = "managedidentity"
        AzureWebJobsStorage__clientId    = a.create_user_assigned_identity ? azurerm_user_assigned_identity.this[k].client_id : null
      } : {}
    )
  }

  app_insights_settings = {
    for k, a in var.function_apps : k => merge(
      a.app_insights_connection_string != null ? { APPLICATIONINSIGHTS_CONNECTION_STRING = a.app_insights_connection_string } : {},
      a.app_insights_connection_string != null && a.create_user_assigned_identity ? {
        APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "ClientId=${azurerm_user_assigned_identity.this[k].client_id};Authorization=AAD"
      } : {},
    )
  }

  effective_app_settings = {
    for k, a in var.function_apps : k => merge(
      { for s, v in local.host_storage_settings[k] : s => v if v != null },
      local.app_insights_settings[k],
      a.app_settings,
    )
  }

}

resource "azurerm_service_plan" "this" {
  for_each = var.service_plans

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name                       = each.key
  os_type                    = each.value.os_type
  sku_name                   = each.value.sku_name
  app_service_environment_id = each.value.app_service_environment_id
  zone_balancing_enabled     = each.value.zone_balancing_enabled
  worker_count               = each.value.worker_count
}

# Dedicated FC1 plans for apps that reference no plan: one call, one running app.
resource "azurerm_service_plan" "auto" {
  for_each = local.auto_plan_apps

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name     = "asp-${each.key}"
  os_type  = "Linux"
  sku_name = "FC1"
}

resource "azurerm_user_assigned_identity" "this" {
  for_each = local.uai_apps

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name = "id-${each.key}"
}

# The backing storage: keyless by default (identity auth end to end); the host and function keys
# API is unavailable keyless, which is documented on the variable.
resource "azurerm_storage_account" "this" {
  for_each = local.storage_create_apps

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name                            = local.storage_account_names[each.key]
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = each.value.storage_shared_access_key_enabled

  # No network rules by default, deliberately: the flex host must reach its deployment container,
  # and locking the account down without VNet integration breaks deploys and cold starts (the
  # well-known flex locked-storage gotcha). Callers with VNet topology restrict it here.
  dynamic "network_rules" {
    for_each = each.value.storage_network_rules != null ? [each.value.storage_network_rules] : []

    content {
      default_action             = network_rules.value.default_action
      bypass                     = network_rules.value.bypass
      ip_rules                   = network_rules.value.ip_rules
      virtual_network_subnet_ids = network_rules.value.virtual_network_subnet_ids
    }
  }
}

resource "azurerm_storage_container" "this" {
  for_each = local.storage_create_apps

  name                  = each.value.storage_container_name
  storage_account_id    = azurerm_storage_account.this[each.key].id
  container_access_type = "private"
}

# The documented flex identity role set, granted BEFORE the app exists so deploy-during-create
# and the host's secrets store work first try.
resource "azurerm_role_assignment" "storage" {
  for_each = local.storage_grants

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.this[each.value.app].principal_id
}

# AAD ingestion for Application Insights when the module owns the identity and knows the AI scope.
resource "azurerm_role_assignment" "app_insights" {
  for_each = { for k, a in var.function_apps : k => a if a.app_insights_id != null && a.create_user_assigned_identity }

  scope                = each.value.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.this[each.key].principal_id
}

resource "azurerm_function_app_flex_consumption" "this" {
  for_each = var.function_apps

  resource_group_name = local.rg.resource_group_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))

  name = each.key
  service_plan_id = coalesce(
    each.value.service_plan_id,
    each.value.service_plan_key != null ? azurerm_service_plan.this[coalesce(each.value.service_plan_key, "-")].id : null,
    try(azurerm_service_plan.auto[each.key].id, null),
  )

  runtime_name    = each.value.runtime_name
  runtime_version = each.value.runtime_version

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = local.storage_container_endpoints[each.key]
  storage_authentication_type       = local.storage_auth[each.key]
  storage_access_key                = local.storage_auth[each.key] == "StorageAccountConnectionString" ? coalesce(each.value.storage_access_key, try(azurerm_storage_account.this[each.key].primary_access_key, null)) : null
  storage_user_assigned_identity_id = local.storage_uai_id[each.key]

  maximum_instance_count = each.value.maximum_instance_count
  instance_memory_in_mb  = each.value.instance_memory_in_mb
  http_concurrency       = each.value.http_concurrency

  https_only                                     = each.value.https_only
  public_network_access_enabled                  = each.value.public_network_access_enabled
  virtual_network_subnet_id                      = each.value.virtual_network_subnet_id
  client_certificate_enabled                     = each.value.client_certificate_enabled
  client_certificate_mode                        = each.value.client_certificate_mode
  client_certificate_exclusion_paths             = each.value.client_certificate_exclusion_paths
  webdeploy_publish_basic_authentication_enabled = each.value.webdeploy_publish_basic_authentication_enabled
  enabled                                        = each.value.enabled

  app_settings = local.effective_app_settings[each.key]

  # Broken upstream for flex (the publish path polls a status endpoint that 404s); passthrough
  # kept for when it is fixed. Use deploy_package for the working one-deploy path.
  zip_deploy_file = each.value.zip_deploy_file

  identity {
    type         = local.identity_blocks[each.key].type
    identity_ids = try(local.identity_blocks[each.key].identity_ids, null)
  }

  dynamic "always_ready" {
    for_each = each.value.always_ready

    content {
      name           = always_ready.value.name
      instance_count = always_ready.value.instance_count
    }
  }

  dynamic "connection_string" {
    for_each = each.value.connection_strings

    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  dynamic "sticky_settings" {
    for_each = each.value.sticky_settings != null ? [each.value.sticky_settings] : []

    content {
      app_setting_names       = sticky_settings.value.app_setting_names
      connection_string_names = sticky_settings.value.connection_string_names
    }
  }

  site_config {
    api_definition_url                            = each.value.site_config.api_definition_url
    api_management_api_id                         = each.value.site_config.api_management_api_id
    app_command_line                              = each.value.site_config.app_command_line
    application_insights_connection_string        = each.value.site_config.application_insights_connection_string
    application_insights_key                      = each.value.site_config.application_insights_key
    container_registry_managed_identity_client_id = each.value.site_config.container_registry_managed_identity_client_id
    container_registry_use_managed_identity       = each.value.site_config.container_registry_use_managed_identity
    default_documents                             = each.value.site_config.default_documents
    elastic_instance_minimum                      = each.value.site_config.elastic_instance_minimum
    health_check_eviction_time_in_min             = each.value.site_config.health_check_eviction_time_in_min
    health_check_path                             = each.value.site_config.health_check_path
    http2_enabled                                 = each.value.site_config.http2_enabled
    ip_restriction_default_action                 = each.value.site_config.ip_restriction_default_action
    load_balancing_mode                           = each.value.site_config.load_balancing_mode
    managed_pipeline_mode                         = each.value.site_config.managed_pipeline_mode
    minimum_tls_version                           = each.value.site_config.minimum_tls_version
    remote_debugging_enabled                      = each.value.site_config.remote_debugging_enabled
    remote_debugging_version                      = each.value.site_config.remote_debugging_version
    runtime_scale_monitoring_enabled              = each.value.site_config.runtime_scale_monitoring_enabled
    scm_ip_restriction_default_action             = each.value.site_config.scm_ip_restriction_default_action
    scm_minimum_tls_version                       = each.value.site_config.scm_minimum_tls_version
    scm_use_main_ip_restriction                   = each.value.site_config.scm_use_main_ip_restriction
    use_32_bit_worker                             = each.value.site_config.use_32_bit_worker
    vnet_route_all_enabled                        = each.value.site_config.vnet_route_all_enabled
    websockets_enabled                            = each.value.site_config.websockets_enabled
    worker_count                                  = each.value.site_config.worker_count

    dynamic "app_service_logs" {
      for_each = each.value.site_config.app_service_logs != null ? [each.value.site_config.app_service_logs] : []

      content {
        disk_quota_mb         = app_service_logs.value.disk_quota_mb
        retention_period_days = app_service_logs.value.retention_period_days
      }
    }

    dynamic "cors" {
      for_each = each.value.site_config.cors != null ? [each.value.site_config.cors] : []

      content {
        allowed_origins     = cors.value.allowed_origins
        support_credentials = cors.value.support_credentials
      }
    }

    dynamic "ip_restriction" {
      for_each = each.value.site_config.ip_restrictions

      content {
        action                    = ip_restriction.value.action
        description               = ip_restriction.value.description
        ip_address                = ip_restriction.value.ip_address
        name                      = ip_restriction.value.name
        priority                  = ip_restriction.value.priority
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id

        dynamic "headers" {
          for_each = coalesce(ip_restriction.value.headers, [])

          content {
            x_azure_fdid      = headers.value.x_azure_fdid
            x_fd_health_probe = headers.value.x_fd_health_probe
            x_forwarded_for   = headers.value.x_forwarded_for
            x_forwarded_host  = headers.value.x_forwarded_host
          }
        }
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = each.value.site_config.scm_ip_restrictions

      content {
        action                    = scm_ip_restriction.value.action
        description               = scm_ip_restriction.value.description
        ip_address                = scm_ip_restriction.value.ip_address
        name                      = scm_ip_restriction.value.name
        priority                  = scm_ip_restriction.value.priority
        service_tag               = scm_ip_restriction.value.service_tag
        virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id

        dynamic "headers" {
          for_each = coalesce(scm_ip_restriction.value.headers, [])

          content {
            x_azure_fdid      = headers.value.x_azure_fdid
            x_fd_health_probe = headers.value.x_fd_health_probe
            x_forwarded_for   = headers.value.x_forwarded_for
            x_forwarded_host  = headers.value.x_forwarded_host
          }
        }
      }
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
          client_id                  = active_directory.value.client_id
          allowed_audiences          = active_directory.value.allowed_audiences
          client_secret              = active_directory.value.client_secret
          client_secret_setting_name = active_directory.value.client_secret_setting_name
        }
      }

      dynamic "facebook" {
        for_each = auth_settings.value.facebook != null ? [auth_settings.value.facebook] : []

        content {
          app_id                  = facebook.value.app_id
          app_secret              = facebook.value.app_secret
          app_secret_setting_name = facebook.value.app_secret_setting_name
          oauth_scopes            = facebook.value.oauth_scopes
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

      dynamic "google" {
        for_each = auth_settings.value.google != null ? [auth_settings.value.google] : []

        content {
          client_id                  = google.value.client_id
          client_secret              = google.value.client_secret
          client_secret_setting_name = google.value.client_secret_setting_name
          oauth_scopes               = google.value.oauth_scopes
        }
      }

      dynamic "microsoft" {
        for_each = auth_settings.value.microsoft != null ? [auth_settings.value.microsoft] : []

        content {
          client_id                  = microsoft.value.client_id
          client_secret              = microsoft.value.client_secret
          client_secret_setting_name = microsoft.value.client_secret_setting_name
          oauth_scopes               = microsoft.value.oauth_scopes
        }
      }

      dynamic "twitter" {
        for_each = auth_settings.value.twitter != null ? [auth_settings.value.twitter] : []

        content {
          consumer_key                 = twitter.value.consumer_key
          consumer_secret              = twitter.value.consumer_secret
          consumer_secret_setting_name = twitter.value.consumer_secret_setting_name
        }
      }
    }
  }

  dynamic "auth_settings_v2" {
    for_each = each.value.auth_settings_v2 != null ? [each.value.auth_settings_v2] : []

    content {
      auth_enabled                            = auth_settings_v2.value.auth_enabled
      config_file_path                        = auth_settings_v2.value.config_file_path
      default_provider                        = auth_settings_v2.value.default_provider
      excluded_paths                          = auth_settings_v2.value.excluded_paths
      forward_proxy_convention                = auth_settings_v2.value.forward_proxy_convention
      forward_proxy_custom_host_header_name   = auth_settings_v2.value.forward_proxy_custom_host_header_name
      forward_proxy_custom_scheme_header_name = auth_settings_v2.value.forward_proxy_custom_scheme_header_name
      http_route_api_prefix                   = auth_settings_v2.value.http_route_api_prefix
      require_authentication                  = auth_settings_v2.value.require_authentication
      require_https                           = auth_settings_v2.value.require_https
      runtime_version                         = auth_settings_v2.value.runtime_version
      unauthenticated_action                  = auth_settings_v2.value.unauthenticated_action

      dynamic "active_directory_v2" {
        for_each = auth_settings_v2.value.active_directory_v2 != null ? [auth_settings_v2.value.active_directory_v2] : []

        content {
          client_id                            = active_directory_v2.value.client_id
          tenant_auth_endpoint                 = active_directory_v2.value.tenant_auth_endpoint
          allowed_applications                 = active_directory_v2.value.allowed_applications
          allowed_audiences                    = active_directory_v2.value.allowed_audiences
          allowed_groups                       = active_directory_v2.value.allowed_groups
          allowed_identities                   = active_directory_v2.value.allowed_identities
          client_secret_certificate_thumbprint = active_directory_v2.value.client_secret_certificate_thumbprint
          client_secret_setting_name           = active_directory_v2.value.client_secret_setting_name
          jwt_allowed_client_applications      = active_directory_v2.value.jwt_allowed_client_applications
          jwt_allowed_groups                   = active_directory_v2.value.jwt_allowed_groups
          login_parameters                     = active_directory_v2.value.login_parameters
          www_authentication_disabled          = active_directory_v2.value.www_authentication_disabled
        }
      }

      dynamic "apple_v2" {
        for_each = auth_settings_v2.value.apple_v2 != null ? [auth_settings_v2.value.apple_v2] : []

        content {
          client_id                  = apple_v2.value.client_id
          client_secret_setting_name = apple_v2.value.client_secret_setting_name
        }
      }

      dynamic "azure_static_web_app_v2" {
        for_each = auth_settings_v2.value.azure_static_web_app_v2 != null ? [auth_settings_v2.value.azure_static_web_app_v2] : []

        content {
          client_id = azure_static_web_app_v2.value.client_id
        }
      }

      dynamic "custom_oidc_v2" {
        for_each = auth_settings_v2.value.custom_oidc_v2

        content {
          client_id                     = custom_oidc_v2.value.client_id
          name                          = custom_oidc_v2.value.name
          openid_configuration_endpoint = custom_oidc_v2.value.openid_configuration_endpoint
          name_claim_type               = custom_oidc_v2.value.name_claim_type
          scopes                        = custom_oidc_v2.value.scopes
        }
      }

      dynamic "facebook_v2" {
        for_each = auth_settings_v2.value.facebook_v2 != null ? [auth_settings_v2.value.facebook_v2] : []

        content {
          app_id                  = facebook_v2.value.app_id
          app_secret_setting_name = facebook_v2.value.app_secret_setting_name
          graph_api_version       = facebook_v2.value.graph_api_version
          login_scopes            = facebook_v2.value.login_scopes
        }
      }

      dynamic "github_v2" {
        for_each = auth_settings_v2.value.github_v2 != null ? [auth_settings_v2.value.github_v2] : []

        content {
          client_id                  = github_v2.value.client_id
          client_secret_setting_name = github_v2.value.client_secret_setting_name
          login_scopes               = github_v2.value.login_scopes
        }
      }

      dynamic "google_v2" {
        for_each = auth_settings_v2.value.google_v2 != null ? [auth_settings_v2.value.google_v2] : []

        content {
          client_id                  = google_v2.value.client_id
          client_secret_setting_name = google_v2.value.client_secret_setting_name
          allowed_audiences          = google_v2.value.allowed_audiences
          login_scopes               = google_v2.value.login_scopes
        }
      }

      dynamic "microsoft_v2" {
        for_each = auth_settings_v2.value.microsoft_v2 != null ? [auth_settings_v2.value.microsoft_v2] : []

        content {
          client_id                  = microsoft_v2.value.client_id
          client_secret_setting_name = microsoft_v2.value.client_secret_setting_name
          allowed_audiences          = microsoft_v2.value.allowed_audiences
          login_scopes               = microsoft_v2.value.login_scopes
        }
      }

      dynamic "twitter_v2" {
        for_each = auth_settings_v2.value.twitter_v2 != null ? [auth_settings_v2.value.twitter_v2] : []

        content {
          consumer_key                 = twitter_v2.value.consumer_key
          consumer_secret_setting_name = twitter_v2.value.consumer_secret_setting_name
        }
      }

      login {
        allowed_external_redirect_urls    = auth_settings_v2.value.login.allowed_external_redirect_urls
        cookie_expiration_convention      = auth_settings_v2.value.login.cookie_expiration_convention
        cookie_expiration_time            = auth_settings_v2.value.login.cookie_expiration_time
        logout_endpoint                   = auth_settings_v2.value.login.logout_endpoint
        nonce_expiration_time             = auth_settings_v2.value.login.nonce_expiration_time
        preserve_url_fragments_for_logins = auth_settings_v2.value.login.preserve_url_fragments_for_logins
        token_refresh_extension_time      = auth_settings_v2.value.login.token_refresh_extension_time
        token_store_enabled               = auth_settings_v2.value.login.token_store_enabled
        token_store_path                  = auth_settings_v2.value.login.token_store_path
        token_store_sas_setting_name      = auth_settings_v2.value.login.token_store_sas_setting_name
        validate_nonce                    = auth_settings_v2.value.login.validate_nonce
      }
    }
  }

  depends_on = [azurerm_role_assignment.storage]
}
