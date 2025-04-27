variable "flex_function_apps" {
  description = "List of Flex‑Consumption Function Apps (keeps original style)"
  type = list(object({
    # ── Core identity ─────────────────────────────────────────────────
    name        = string
    rg_name     = string
    location    = string

    # ── Plan creation ─────────────────────────────────────────────────
    create_new_app_service_plan = optional(bool, true)
    app_service_plan_name       = optional(string)
    service_plan_id             = optional(string)
    os_type                     = optional(string, "Linux")
    sku_name                    = optional(string, "FC1")

    # ── Flex‑specific mandatory fields ───────────────────────────────
    runtime_name                = string                 # "dotnet-isolated" | "python" | "node" | "java"
    runtime_version             = string                 # e.g. "8.0", "3.11"
    storage_container_type      = optional(string, "blobContainer")
    storage_user_assigned_identity_id = optional(string)
    storage_container_endpoint  = string                 # "https://<account>.blob.core.windows.net/<container>"
    storage_authentication_type = optional(string, "SystemAssignedIdentity") # or "StorageAccountConnectionString"
    storage_access_key          = optional(string)       # only when auth type is connection string
    maximum_instance_count      = optional(number)       # default from portal (100) if omitted
    instance_memory_in_mb       = optional(number, 2048) # must be 2048 or 4096

    app_settings                       = map(string)
    tags                               = optional(map(string))
    client_certificate_enabled         = optional(bool)
    client_certificate_exclusion_paths = optional(string)
    client_certificate_mode            = optional(string)
    enabled                            = optional(bool, true)
    content_share_force_disabled       = optional(bool)
    identity_type                      = optional(string)
    public_network_access_enabled      = optional(bool, true)
    virtual_network_subnet_id          = optional(string)
    webdeploy_publish_basic_authentication_enabled = optional(bool, false)
    zip_deploy_file                    = optional(string)

    identity_ids                 = optional(list(string))

    # ── Application Insights options (unchanged) ─────────────────────
    create_new_app_insights = optional(bool, false)
    workspace_id            = optional(string)
    app_insights_name       = optional(string)
    app_insights_type       = optional(string, "Web")
    app_insights_daily_cap_in_gb                       = optional(number)
    app_insights_daily_data_cap_notifications_disabled = optional(bool, false)
    app_insights_internet_ingestion_enabled            = optional(bool)
    app_insights_internet_query_enabled                = optional(bool)
    app_insights_local_authentication_disabled         = optional(bool, true)
    app_insights_force_customer_storage_for_profile    = optional(bool, false)
    app_insights_sampling_percentage                   = optional(number, 100)

    sticky_settings = optional(object({
      app_setting_names       = optional(list(string))
      connection_string_names = optional(list(string))
    }))

    connection_string = optional(object({
      name  = optional(string)
      type  = optional(string)
      value = optional(string)
    }))
    auth_settings_v2 = optional(object({
      auth_enabled                            = optional(bool)
      runtime_version                         = optional(string)
      config_file_path                        = optional(string)
      require_authentication                  = optional(bool)
      unauthenticated_action                  = optional(string)
      default_provider                        = optional(string)
      excluded_paths                          = optional(list(string))
      require_https                           = optional(bool)
      http_route_api_prefix                   = optional(string)
      forward_proxy_convention                = optional(string)
      forward_proxy_custom_host_header_name   = optional(string)
      forward_proxy_custom_scheme_header_name = optional(string)
      apple_v2 = optional(object({
        client_id                  = string
        client_secret_setting_name = string
        login_scopes               = list(string)
      }))
      active_directory_v2 = optional(object({
        client_id                            = string
        tenant_auth_endpoint                 = string
        client_secret_setting_name           = optional(string)
        client_secret_certificate_thumbprint = optional(string)
        jwt_allowed_groups                   = optional(list(string))
        jwt_allowed_client_applications      = optional(list(string))
        www_authentication_disabled          = optional(bool)
        allowed_groups                       = optional(list(string))
        allowed_identities                   = optional(list(string))
        allowed_applications                 = optional(list(string))
        login_parameters                     = optional(map(string))
        allowed_audiences                    = optional(list(string))
      }))
      azure_static_web_app_v2 = optional(object({
        client_id = string
      }))
      custom_oidc_v2 = optional(list(object({
        name                          = string
        client_id                     = string
        openid_configuration_endpoint = string
        name_claim_type               = optional(string)
        scopes                        = optional(list(string))
        client_credential_method      = string
        client_secret_setting_name    = string
        authorisation_endpoint        = string
        token_endpoint                = string
        issuer_endpoint               = string
        certification_uri             = string
      })))
      facebook_v2 = optional(object({
        app_id                  = string
        app_secret_setting_name = string
        graph_api_version       = optional(string)
        login_scopes            = optional(list(string))
      }))
      github_v2 = optional(object({
        client_id                  = string
        client_secret_setting_name = string
        login_scopes               = optional(list(string))
      }))
      google_v2 = optional(object({
        client_id                  = string
        client_secret_setting_name = string
        allowed_audiences          = optional(list(string))
        login_scopes               = optional(list(string))
      }))
      microsoft_v2 = optional(object({
        client_id                  = string
        client_secret_setting_name = string
        allowed_audiences          = optional(list(string))
        login_scopes               = optional(list(string))
      }))
      twitter_v2 = optional(object({
        consumer_key                 = string
        consumer_secret_setting_name = string
      }))
      login = optional(object({
        logout_endpoint                   = optional(string)
        token_store_enabled               = optional(bool)
        token_refresh_extension_time      = optional(number)
        token_store_path                  = optional(string)
        token_store_sas_setting_name      = optional(string)
        preserve_url_fragments_for_logins = optional(bool)
        allowed_external_redirect_urls    = optional(list(string))
        cookie_expiration_convention      = optional(string)
        cookie_expiration_time            = optional(string)
        validate_nonce                    = optional(bool)
        nonce_expiration_time             = optional(string)
      }))
    }))
    auth_settings = optional(object({
      enabled                        = optional(bool)
      additional_login_parameters    = optional(map(string))
      allowed_external_redirect_urls = optional(list(string))
      default_provider               = optional(string)
      issuer                         = optional(string)
      runtime_version                = optional(string)
      token_refresh_extension_hours  = optional(number)
      token_store_enabled            = optional(bool)
      unauthenticated_client_action  = optional(string)
      active_directory = optional(object({
        client_id         = optional(string)
        client_secret     = optional(string)
        allowed_audiences = optional(list(string))
      }))
      facebook = optional(object({
        app_id       = optional(string)
        app_secret   = optional(string)
        oauth_scopes = optional(list(string))
      }))
      google = optional(object({
        client_id     = optional(string)
        client_secret = optional(string)
        oauth_scopes  = optional(list(string))
      }))
      microsoft = optional(object({
        client_id     = optional(string)
        client_secret = optional(string)
        oauth_scopes  = optional(list(string))
      }))
      twitter = optional(object({
        consumer_key    = optional(string)
        consumer_secret = optional(string)
      }))
      github = optional(object({
        client_id                  = optional(string)
        client_secret              = optional(string)
        client_secret_setting_name = optional(string)
        oauth_scopes               = optional(list(string))
      }))
    }))
    site_config = optional(object({
      api_definition_url                            = optional(string)
      api_management_api_id                         = optional(string)
      app_command_line                              = optional(string)
      application_insights_connection_string        = optional(string)
      application_insights_key                      = optional(string)
      container_registry_managed_identity_client_id = optional(string)
      container_registry_use_managed_identity       = optional(bool)
      elastic_instance_minimum                      = optional(number)
      health_check_path                             = optional(string)
      health_check_eviction_time_in_min             = optional(number)
      http2_enabled                                 = optional(bool)
      load_balancing_mode                           = optional(string)
      managed_pipeline_mode                         = optional(string)
      minimum_tls_version                           = optional(string)
      remote_debugging_enabled                      = optional(bool)
      remote_debugging_version                      = optional(string)
      runtime_scale_monitoring_enabled              = optional(bool)
      scm_minimum_tls_version                       = optional(string)
      scm_use_main_ip_restriction                   = optional(bool)
      use_32_bit_worker                             = optional(bool)
      websockets_enabled                            = optional(bool)
      worker_count                                  = optional(number)
      default_documents                             = optional(list(string))
      app_service_logs = optional(object({
        disk_quota_mb         = optional(number)
        retention_period_days = optional(number)
      }))
      cors = optional(object({
        allowed_origins     = optional(list(string))
        support_credentials = optional(bool)
      }))
      ip_restriction = optional(list(object({
        ip_address                = optional(string)
        service_tag               = optional(string)
        virtual_network_subnet_id = optional(string)
        name                      = optional(string)
        priority                  = optional(number)
        action                    = optional(string)
        headers = optional(object({
          x_azure_fdid      = optional(string)
          x_fd_health_probe = optional(string)
          x_forwarded_for   = optional(string)
          x_forwarded_host  = optional(string)
        }))
      })))
      scm_ip_restriction = optional(list(object({
        ip_address                = optional(string)
        service_tag               = optional(string)
        virtual_network_subnet_id = optional(string)
        name                      = optional(string)
        priority                  = optional(number)
        action                    = optional(string)
        headers = optional(object({
          x_azure_fdid      = optional(string)
          x_fd_health_probe = optional(string)
          x_forwarded_for   = optional(string)
          x_forwarded_host  = optional(string)
        }))
      })))
    }))
  }))
  default = []
}
