# Tests for the module. azurerm is mocked (no credentials, no cloud):
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {
  # Downstream resources parse these ids and compose these endpoints, so they need real shapes.
  mock_resource "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Storage/storageAccounts/stmock"
      primary_blob_endpoint = "https://stmock.blob.core.windows.net/"
      primary_access_key    = "bW9ja2tleQ=="
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mock"
      principal_id = "00000000-0000-0000-0000-00000000aaaa"
      client_id    = "00000000-0000-0000-0000-00000000bbbb"
    }
  }

  mock_resource "azurerm_service_plan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Web/serverFarms/asp-mock"
    }
  }
}

variables {
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001"
  location          = "uksouth"
  tags              = { Environment = "tst" }
}

# One app, nothing but the runtime: dedicated FC1 plan, keyless storage, a UAI granted the full
# documented role set before the app, and the identity host storage settings wired.
run "fast_to_get_going" {
  command = apply

  variables {
    function_apps = {
      "func-app-ldo-uks-tst-01" = {
        runtime_name    = "python"
        runtime_version = "3.12"
      }
    }
  }

  assert {
    condition     = azurerm_service_plan.auto["func-app-ldo-uks-tst-01"].sku_name == "FC1"
    error_message = "An app with no plan reference should get a dedicated FC1 plan."
  }

  assert {
    condition     = azurerm_storage_account.this["func-app-ldo-uks-tst-01"].shared_access_key_enabled == false
    error_message = "Created storage should be keyless by default."
  }

  assert {
    condition     = length([for k, v in azurerm_role_assignment.storage : k if startswith(k, "func-app-ldo-uks-tst-01|")]) == 4
    error_message = "The full documented role set (Owner, Blob, Queue, Table) should be granted."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-app-ldo-uks-tst-01"].storage_authentication_type == "UserAssignedIdentity"
    error_message = "Storage auth should derive to UserAssignedIdentity with the module UAI."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-app-ldo-uks-tst-01"].app_settings["AzureWebJobsStorage__credential"] == "managedidentity"
    error_message = "The identity host storage settings should be wired automatically."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-app-ldo-uks-tst-01"].app_settings["AzureWebJobsStorage"] == ""
    error_message = "The bare AzureWebJobsStorage setting should be pinned empty on keyless apps (provider #29149 re-injects a key-based string that breaks the host key APIs)."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-app-ldo-uks-tst-01"].https_only == true
    error_message = "https_only should default true (the provider default is false)."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-app-ldo-uks-tst-01"].identity[0].type == "SystemAssigned, UserAssigned"
    error_message = "The identity block should carry both kinds with the module UAI."
  }
}

# Plans as a map: two apps share one plan; a third brings its own plan id.
run "plan_shapes" {
  command = apply

  variables {
    service_plans = {
      "asp-shared-ldo-uks-tst-01" = {
        sku_name               = "FC1"
        zone_balancing_enabled = false
      }
    }

    function_apps = {
      "func-a-ldo-uks-tst-01" = {
        runtime_name     = "python"
        runtime_version  = "3.12"
        service_plan_key = "asp-shared-ldo-uks-tst-01"
      }
      "func-b-ldo-uks-tst-01" = {
        runtime_name     = "node"
        runtime_version  = "20"
        service_plan_key = "asp-shared-ldo-uks-tst-01"
      }
      "func-c-ldo-uks-tst-01" = {
        runtime_name    = "dotnet-isolated"
        runtime_version = "9.0"
        service_plan_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Web/serverFarms/asp-byo"
      }
    }
  }

  assert {
    condition     = length(azurerm_service_plan.auto) == 0
    error_message = "No dedicated plans should be created when every app references one."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-a-ldo-uks-tst-01"].service_plan_id == azurerm_function_app_flex_consumption.this["func-b-ldo-uks-tst-01"].service_plan_id
    error_message = "Apps sharing a plan key should land on the same plan."
  }

  assert {
    condition     = endswith(azurerm_function_app_flex_consumption.this["func-c-ldo-uks-tst-01"].service_plan_id, "asp-byo")
    error_message = "A bring-your-own plan id should be used as-is."
  }
}

# Bring-your-own storage by id: no account created, the endpoint is constructed, grants still land.
run "byo_storage_by_id" {
  command = apply

  variables {
    function_apps = {
      "func-byo-ldo-uks-tst-01" = {
        runtime_name           = "python"
        runtime_version        = "3.12"
        create_storage_account = false
        storage_account_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Storage/storageAccounts/stbyoldoukstst01"
      }
    }
  }

  assert {
    condition     = length(azurerm_storage_account.this) == 0
    error_message = "No storage account should be created for the BYO shape."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-byo-ldo-uks-tst-01"].storage_container_endpoint == "https://stbyoldoukstst01.blob.core.windows.net/app-packages"
    error_message = "The container endpoint should be constructed from the BYO account id."
  }

  assert {
    condition     = length([for k, v in azurerm_role_assignment.storage : k if startswith(k, "func-byo-ldo-uks-tst-01|")]) == 4
    error_message = "Grants should still land on BYO storage (the module has the scope)."
  }
}

# The raw endpoint escape hatch: nothing created, nothing granted, no host settings wired.
run "raw_endpoint_escape_hatch" {
  command = apply

  variables {
    function_apps = {
      "func-raw-ldo-uks-tst-01" = {
        runtime_name               = "python"
        runtime_version            = "3.12"
        create_storage_account     = false
        storage_container_endpoint = "https://stelsewhere.blob.core.windows.net/packages"
      }
    }
  }

  assert {
    condition     = length(azurerm_role_assignment.storage) == 0
    error_message = "The raw endpoint shape grants nothing."
  }

  assert {
    condition     = !contains(keys(azurerm_function_app_flex_consumption.this["func-raw-ldo-uks-tst-01"].app_settings), "AzureWebJobsStorage__accountName") && !contains(keys(azurerm_function_app_flex_consumption.this["func-raw-ldo-uks-tst-01"].app_settings), "AzureWebJobsStorage")
    error_message = "No host storage settings should be wired for the raw endpoint shape."
  }
}

# Keys-on connection string auth: the created account's key feeds the app.
run "connection_string_auth" {
  command = apply

  variables {
    function_apps = {
      "func-keys-ldo-uks-tst-01" = {
        runtime_name                      = "python"
        runtime_version                   = "3.12"
        storage_shared_access_key_enabled = true
        storage_authentication_type       = "StorageAccountConnectionString"
        create_user_assigned_identity     = false
        identity                          = { type = "SystemAssigned" }
      }
    }
  }

  assert {
    condition     = azurerm_storage_account.this["func-keys-ldo-uks-tst-01"].shared_access_key_enabled == true
    error_message = "Keys should be enabled on request."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-keys-ldo-uks-tst-01"].storage_access_key != null
    error_message = "The created account's key should feed connection string auth."
  }
}

# An identity-less app: keys-on with no identity block at all. Storage auth derives to
# connection string and the resource carries no identity.
run "no_identity_at_all" {
  command = apply

  variables {
    function_apps = {
      "func-noid-ldo-uks-tst-01" = {
        runtime_name                      = "python"
        runtime_version                   = "3.12"
        storage_shared_access_key_enabled = true
        create_user_assigned_identity     = false
      }
    }
  }

  assert {
    condition     = length(azurerm_function_app_flex_consumption.this["func-noid-ldo-uks-tst-01"].identity) == 0
    error_message = "No identity block should be present when none is created or brought."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.this["func-noid-ldo-uks-tst-01"].storage_authentication_type == "StorageAccountConnectionString"
    error_message = "Storage auth should derive to connection string for an identity-less app."
  }

  assert {
    condition     = !contains(keys(azurerm_function_app_flex_consumption.this["func-noid-ldo-uks-tst-01"].app_settings), "AzureWebJobsStorage__accountName")
    error_message = "No identity host storage settings should be wired without an identity."
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.this) == 0
    error_message = "No user assigned identity should be created."
  }
}

# App Insights wiring: the connection string setting plus the AAD ingestion auth string and grant.
run "app_insights_wiring" {
  command = apply

  variables {
    function_apps = {
      "func-ai-ldo-uks-tst-01" = {
        runtime_name                         = "python"
        runtime_version                      = "3.12"
        app_insights_connection_string       = "InstrumentationKey=00000000-0000-0000-0000-000000000000"
        app_insights_id                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"
        grant_app_insights_metrics_publisher = true
      }
    }
  }

  assert {
    condition     = startswith(azurerm_function_app_flex_consumption.this["func-ai-ldo-uks-tst-01"].app_settings["APPLICATIONINSIGHTS_AUTHENTICATION_STRING"], "ClientId=")
    error_message = "The AAD ingestion auth string should be wired with the module UAI."
  }

  assert {
    condition     = length(azurerm_role_assignment.app_insights) == 1
    error_message = "Monitoring Metrics Publisher should be granted on the App Insights scope."
  }
}

# zip_deploy_file trips the broken-upstream steer.
run "flags_zip_deploy_file" {
  command = apply

  variables {
    function_apps = {
      "func-zip-ldo-uks-tst-01" = {
        runtime_name    = "python"
        runtime_version = "3.12"
        zip_deploy_file = "./app.zip"
      }
    }
  }

  expect_failures = [check.zip_deploy_file_is_broken_upstream]
}

# Bring-your-own identity with module-managed storage trips the caller-grants warning.
run "flags_byo_identity" {
  command = apply

  variables {
    function_apps = {
      "func-own-ldo-uks-tst-01" = {
        runtime_name                  = "python"
        runtime_version               = "3.12"
        create_user_assigned_identity = false
        identity = {
          type         = "UserAssigned"
          identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-own"]
        }
      }
    }
  }

  expect_failures = [check.byo_identity_needs_caller_grants]
}

# Rejects: bad runtime, both plan refs, bad memory, two storage shapes, keyless connection string,
# CORS wildcard with credentials, identity alongside create_user_assigned_identity.
run "rejects_bad_runtime" {
  command = plan

  variables {
    function_apps = {
      bad = { runtime_name = "ruby", runtime_version = "3" }
    }
  }

  expect_failures = [var.function_apps]
}

run "rejects_both_plan_refs" {
  command = plan

  variables {
    service_plans = { "asp-x" = {} }
    function_apps = {
      bad = {
        runtime_name     = "python"
        runtime_version  = "3.12"
        service_plan_key = "asp-x"
        service_plan_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-x/providers/Microsoft.Web/serverFarms/asp-y"
      }
    }
  }

  expect_failures = [var.function_apps]
}

run "rejects_bad_memory" {
  command = plan

  variables {
    function_apps = {
      bad = { runtime_name = "python", runtime_version = "3.12", instance_memory_in_mb = 1024 }
    }
  }

  expect_failures = [var.function_apps]
}

run "rejects_two_storage_shapes" {
  command = plan

  variables {
    function_apps = {
      bad = {
        runtime_name       = "python"
        runtime_version    = "3.12"
        storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-x/providers/Microsoft.Storage/storageAccounts/stx"
      }
    }
  }

  expect_failures = [var.function_apps]
}

run "rejects_keyless_connection_string" {
  command = plan

  variables {
    function_apps = {
      bad = {
        runtime_name                = "python"
        runtime_version             = "3.12"
        storage_authentication_type = "StorageAccountConnectionString"
      }
    }
  }

  expect_failures = [var.function_apps]
}

run "rejects_cors_wildcard_with_credentials" {
  command = plan

  variables {
    function_apps = {
      bad = {
        runtime_name    = "python"
        runtime_version = "3.12"
        site_config = {
          cors = { allowed_origins = ["*"], support_credentials = true }
        }
      }
    }
  }

  expect_failures = [var.function_apps]
}

run "rejects_identity_with_create_uai" {
  command = plan

  variables {
    function_apps = {
      bad = {
        runtime_name    = "python"
        runtime_version = "3.12"
        identity        = { type = "SystemAssigned" }
      }
    }
  }

  expect_failures = [var.function_apps]
}
