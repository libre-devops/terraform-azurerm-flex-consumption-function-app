variable "function_apps" {
  description = <<DESC
Flex consumption function apps keyed by name. Fast to get going: an entry with just runtime_name
and runtime_version gets a dedicated FC1 plan, a keyless storage account with a deployment
container, a user-assigned identity granted the full documented role set, and the identity-based
host storage app settings wired automatically. Flexible when it matters: every default has an
explicit override.

PLAN: exactly one of service_plan_key (a plan from service_plans), service_plan_id (bring your
own), or neither (dedicated FC1 plan created).

STORAGE, three shapes: created (default), bring-your-own account via storage_account_id (the
module still builds the container and can still grant roles because it has the scope), or the raw
storage_container_endpoint escape hatch (no grants, caller owns all wiring).
storage_shared_access_key_enabled defaults FALSE (keyless): deploys and runtime work with
identity auth, with one documented limitation: the host and function keys API is unavailable, so
keyless apps should use anonymous or AAD (Easy Auth) trigger auth; set it true if you need
function-key auth. When keyless identity auth is active the module wires
AzureWebJobsStorage__accountName/__credential/__clientId automatically
(wire_host_storage_settings = false to opt out).

IDENTITY: the module creates a user-assigned identity per app by default
(create_user_assigned_identity), because system-assigned plus deploy-during-create is a bootstrap
deadlock (the grant needs the principal id, the deploy needs the grant). Pass identity to bring
your own (the module then grants nothing on storage: the identity owner does).

DEPLOY: push the package from outside the resource with one-deploy (see the complete example:
archive_file plus az functionapp deployment source config-zip keyed on the package hash). The
azurerm zip_deploy_file publish path is broken upstream for flex and stays as a passthrough; an
ARM-native pull deploy cannot work keyless because one-deploy fetches packageUri anonymously.

APP INSIGHTS: pass app_insights_connection_string to wire the app setting; with an app_insights_id
and a module-created identity the AAD ingestion auth string and Monitoring Metrics Publisher
grant are wired too.
DESC

  type = map(object({
    runtime_name    = string
    runtime_version = string

    service_plan_key = optional(string)
    service_plan_id  = optional(string)

    # Storage (three shapes; see description).
    create_storage_account                    = optional(bool, true)
    storage_account_name                      = optional(string)
    storage_account_id                        = optional(string)
    storage_container_endpoint                = optional(string)
    storage_container_name                    = optional(string, "app-packages")
    storage_shared_access_key_enabled         = optional(bool, false)
    storage_infrastructure_encryption_enabled = optional(bool, true)
    storage_authentication_type               = optional(string)
    storage_access_key                        = optional(string)
    storage_role_names                        = optional(list(string), ["Storage Blob Data Owner", "Storage Blob Data Contributor", "Storage Queue Data Contributor", "Storage Table Data Contributor"])
    storage_account_replication_type          = optional(string, "LRS")
    storage_network_rules = optional(object({
      default_action             = string
      bypass                     = optional(list(string), ["AzureServices"])
      ip_rules                   = optional(list(string))
      virtual_network_subnet_ids = optional(list(string))
    }))
    wire_host_storage_settings = optional(bool, true)

    # Identity.
    create_user_assigned_identity = optional(bool, true)
    identity = optional(object({
      type         = string
      identity_ids = optional(list(string))
    }))

    # Observability.
    app_insights_connection_string = optional(string)
    app_insights_id                = optional(string)

    # Scale and runtime.
    maximum_instance_count = optional(number)
    instance_memory_in_mb  = optional(number, 2048)
    http_concurrency       = optional(number)
    always_ready = optional(list(object({
      name           = string
      instance_count = optional(number)
    })), [])

    # Security and networking.
    https_only                                     = optional(bool, true)
    public_network_access_enabled                  = optional(bool, true)
    virtual_network_subnet_id                      = optional(string)
    client_certificate_enabled                     = optional(bool)
    client_certificate_mode                        = optional(string)
    client_certificate_exclusion_paths             = optional(string)
    webdeploy_publish_basic_authentication_enabled = optional(bool)
    enabled                                        = optional(bool, true)

    # Deployment. zip_deploy_file is broken upstream for flex (its publish poll 404s); the
    # supported pattern is pushing the package with one-deploy from OUTSIDE the resource (see the
    # complete example: archive_file + az functionapp deployment source config-zip keyed on the
    # package hash). An ARM-native pull deploy is impossible keyless: one-deploy fetches
    # packageUri anonymously (verified live), and keyless accounts cannot mint SAS.
    zip_deploy_file = optional(string)

    # Settings.
    app_settings = optional(map(string), {})
    connection_strings = optional(list(object({
      name  = string
      type  = string
      value = string
    })), [])
    sticky_settings = optional(object({
      app_setting_names       = optional(list(string))
      connection_string_names = optional(list(string))
    }))

    site_config = optional(object({
      api_definition_url                            = optional(string)
      api_management_api_id                         = optional(string)
      app_command_line                              = optional(string)
      application_insights_connection_string        = optional(string)
      application_insights_key                      = optional(string)
      container_registry_managed_identity_client_id = optional(string)
      container_registry_use_managed_identity       = optional(bool)
      default_documents                             = optional(list(string))
      elastic_instance_minimum                      = optional(number)
      health_check_eviction_time_in_min             = optional(number)
      health_check_path                             = optional(string)
      http2_enabled                                 = optional(bool)
      ip_restriction_default_action                 = optional(string)
      load_balancing_mode                           = optional(string)
      managed_pipeline_mode                         = optional(string)
      minimum_tls_version                           = optional(string)
      remote_debugging_enabled                      = optional(bool)
      remote_debugging_version                      = optional(string)
      runtime_scale_monitoring_enabled              = optional(bool)
      scm_ip_restriction_default_action             = optional(string)
      scm_minimum_tls_version                       = optional(string)
      scm_use_main_ip_restriction                   = optional(bool)
      use_32_bit_worker                             = optional(bool)
      vnet_route_all_enabled                        = optional(bool)
      websockets_enabled                            = optional(bool)
      worker_count                                  = optional(number)

      app_service_logs = optional(object({
        disk_quota_mb         = optional(number)
        retention_period_days = optional(number)
      }))

      cors = optional(object({
        allowed_origins     = optional(list(string))
        support_credentials = optional(bool)
      }))

      ip_restrictions = optional(list(object({
        action                    = optional(string)
        description               = optional(string)
        ip_address                = optional(string)
        name                      = optional(string)
        priority                  = optional(number)
        service_tag               = optional(string)
        virtual_network_subnet_id = optional(string)
        headers = optional(list(object({
          x_azure_fdid      = optional(list(string))
          x_fd_health_probe = optional(list(string))
          x_forwarded_for   = optional(list(string))
          x_forwarded_host  = optional(list(string))
        })))
      })), [])

      scm_ip_restrictions = optional(list(object({
        action                    = optional(string)
        description               = optional(string)
        ip_address                = optional(string)
        name                      = optional(string)
        priority                  = optional(number)
        service_tag               = optional(string)
        virtual_network_subnet_id = optional(string)
        headers = optional(list(object({
          x_azure_fdid      = optional(list(string))
          x_fd_health_probe = optional(list(string))
          x_forwarded_for   = optional(list(string))
          x_forwarded_host  = optional(list(string))
        })))
      })), [])
    }), {})

    auth_settings = optional(object({
      enabled                        = bool
      additional_login_parameters    = optional(map(string))
      allowed_external_redirect_urls = optional(list(string))
      default_provider               = optional(string)
      issuer                         = optional(string)
      runtime_version                = optional(string)
      token_refresh_extension_hours  = optional(number)
      token_store_enabled            = optional(bool)
      unauthenticated_client_action  = optional(string)

      active_directory = optional(object({
        client_id                  = string
        allowed_audiences          = optional(list(string))
        client_secret              = optional(string)
        client_secret_setting_name = optional(string)
      }))
      facebook = optional(object({
        app_id                  = string
        app_secret              = optional(string)
        app_secret_setting_name = optional(string)
        oauth_scopes            = optional(list(string))
      }))
      github = optional(object({
        client_id                  = string
        client_secret              = optional(string)
        client_secret_setting_name = optional(string)
        oauth_scopes               = optional(list(string))
      }))
      google = optional(object({
        client_id                  = string
        client_secret              = optional(string)
        client_secret_setting_name = optional(string)
        oauth_scopes               = optional(list(string))
      }))
      microsoft = optional(object({
        client_id                  = string
        client_secret              = optional(string)
        client_secret_setting_name = optional(string)
        oauth_scopes               = optional(list(string))
      }))
      twitter = optional(object({
        consumer_key                 = string
        consumer_secret              = optional(string)
        consumer_secret_setting_name = optional(string)
      }))
    }))

    auth_settings_v2 = optional(object({
      auth_enabled                            = optional(bool)
      config_file_path                        = optional(string)
      default_provider                        = optional(string)
      excluded_paths                          = optional(list(string))
      forward_proxy_convention                = optional(string)
      forward_proxy_custom_host_header_name   = optional(string)
      forward_proxy_custom_scheme_header_name = optional(string)
      http_route_api_prefix                   = optional(string)
      require_authentication                  = optional(bool)
      require_https                           = optional(bool)
      runtime_version                         = optional(string)
      unauthenticated_action                  = optional(string)

      active_directory_v2 = optional(object({
        client_id                            = string
        tenant_auth_endpoint                 = string
        allowed_applications                 = optional(list(string))
        allowed_audiences                    = optional(list(string))
        allowed_groups                       = optional(list(string))
        allowed_identities                   = optional(list(string))
        client_secret_certificate_thumbprint = optional(string)
        client_secret_setting_name           = optional(string)
        jwt_allowed_client_applications      = optional(list(string))
        jwt_allowed_groups                   = optional(list(string))
        login_parameters                     = optional(map(string))
        www_authentication_disabled          = optional(bool)
      }))
      apple_v2 = optional(object({
        client_id                  = string
        client_secret_setting_name = string
      }))
      azure_static_web_app_v2 = optional(object({
        client_id = string
      }))
      custom_oidc_v2 = optional(list(object({
        client_id                     = string
        name                          = string
        openid_configuration_endpoint = string
        name_claim_type               = optional(string)
        scopes                        = optional(list(string))
      })), [])
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
        allowed_external_redirect_urls    = optional(list(string))
        cookie_expiration_convention      = optional(string)
        cookie_expiration_time            = optional(string)
        logout_endpoint                   = optional(string)
        nonce_expiration_time             = optional(string)
        preserve_url_fragments_for_logins = optional(bool)
        token_refresh_extension_time      = optional(number)
        token_store_enabled               = optional(bool)
        token_store_path                  = optional(string)
        token_store_sas_setting_name      = optional(string)
        validate_nonce                    = optional(bool)
      }), {})
    }))

    tags = optional(map(string))
  }))
  default = {}

  validation {
    condition     = alltrue([for a in values(var.function_apps) : contains(["node", "dotnet-isolated", "powershell", "python", "java", "custom"], a.runtime_name)])
    error_message = "runtime_name must be one of node, dotnet-isolated, powershell, python, java, custom."
  }

  validation {
    condition     = alltrue([for a in values(var.function_apps) : !(a.service_plan_key != null && a.service_plan_id != null)])
    error_message = "An app takes service_plan_key or service_plan_id, not both (or neither, for a dedicated FC1 plan)."
  }

  validation {
    condition     = alltrue([for a in values(var.function_apps) : a.service_plan_key == null || contains(keys(var.service_plans), coalesce(a.service_plan_key, "-"))])
    error_message = "service_plan_key must reference a key in service_plans."
  }

  validation {
    condition     = alltrue([for a in values(var.function_apps) : contains([512, 2048, 4096], a.instance_memory_in_mb)])
    error_message = "instance_memory_in_mb must be 512, 2048, or 4096 (the flex consumption instance sizes)."
  }

  validation {
    condition     = alltrue([for a in values(var.function_apps) : a.maximum_instance_count == null ? true : (a.maximum_instance_count >= 1 && a.maximum_instance_count <= 1000)])
    error_message = "maximum_instance_count must be between 1 and 1000."
  }

  validation {
    condition = alltrue([
      for a in values(var.function_apps) :
      length([for x in [a.create_storage_account ? "create" : null, a.storage_account_id, a.storage_container_endpoint] : x if x != null]) == 1
    ])
    error_message = "Each app takes exactly one storage shape: create_storage_account = true (the default; set it false for the other shapes), storage_account_id (bring your own account), or storage_container_endpoint (raw escape hatch)."
  }

  validation {
    condition = alltrue([
      for a in values(var.function_apps) :
      a.storage_authentication_type == null ? true : contains(["StorageAccountConnectionString", "SystemAssignedIdentity", "UserAssignedIdentity"], a.storage_authentication_type)
    ])
    error_message = "storage_authentication_type must be StorageAccountConnectionString, SystemAssignedIdentity, or UserAssignedIdentity (or omitted to derive from the identity setup)."
  }

  validation {
    condition = alltrue([
      for a in values(var.function_apps) :
      a.storage_authentication_type != "StorageAccountConnectionString" ? true : (a.storage_shared_access_key_enabled || !a.create_storage_account)
    ])
    error_message = "StorageAccountConnectionString auth needs access keys: set storage_shared_access_key_enabled = true on created storage (keyless and connection strings cannot coexist)."
  }

  validation {
    condition = alltrue([
      for a in values(var.function_apps) :
      a.storage_authentication_type != "StorageAccountConnectionString" || !a.create_storage_account ? (a.storage_authentication_type == "StorageAccountConnectionString" && !a.create_storage_account ? a.storage_access_key != null : true) : true
    ])
    error_message = "StorageAccountConnectionString auth on bring-your-own storage needs storage_access_key."
  }



  validation {
    condition     = alltrue([for a in values(var.function_apps) : a.client_certificate_mode == null ? true : contains(["Required", "Optional", "OptionalInteractiveUser"], a.client_certificate_mode)])
    error_message = "client_certificate_mode must be Required, Optional, or OptionalInteractiveUser."
  }

  validation {
    condition = alltrue([
      for a in values(var.function_apps) :
      try(a.site_config.cors, null) == null ? true : !(coalesce(a.site_config.cors.support_credentials, false) && contains(coalesce(a.site_config.cors.allowed_origins, []), "*"))
    ])
    error_message = "CORS cannot combine support_credentials = true with a wildcard allowed origin (the service rejects it)."
  }

  validation {
    condition     = alltrue([for a in values(var.function_apps) : a.identity == null || !a.create_user_assigned_identity])
    error_message = "Set create_user_assigned_identity = false when bringing your own identity block."
  }
}

variable "location" {
  description = "The Azure region the plans, apps, and created storage live in."
  type        = string
  nullable    = false
}

variable "resource_group_id" {
  description = "The id of the resource group everything lands in. Parsed for the resource group name."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.resource_group_id))
    error_message = "resource_group_id must be a resource group id (/subscriptions/<sub>/resourceGroups/<name>)."
  }
}

variable "service_plans" {
  description = <<DESC
Service plans the module creates, keyed by name. Multiple function apps can share one plan by
referencing its key, even though flex consumption is commonly one app per plan today. sku_name is
not welded to FC1 and app_service_environment_id allows App Service Environment placement, so the
map stays general purpose. Apps that reference no plan at all get a dedicated FC1 plan named
asp-<app key> automatically (one module call = running app).
DESC

  type = map(object({
    os_type                    = optional(string, "Linux")
    sku_name                   = optional(string, "FC1")
    app_service_environment_id = optional(string)
    zone_balancing_enabled     = optional(bool)
    worker_count               = optional(number)
    tags                       = optional(map(string))
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to everything the module creates (merged with any per-item tags)."
  type        = map(string)
  default     = {}
}
