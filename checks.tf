# check blocks run after every plan and apply and warn (without blocking) on configuration that would
# quietly misbehave.

# The azurerm zip_deploy_file publish path is broken upstream for flex consumption (it polls a
# deployment status endpoint that 404s even on healthy apps): push with one-deploy from outside
# the resource instead (see the complete example).
check "zip_deploy_file_is_broken_upstream" {
  assert {
    condition     = alltrue([for a in values(var.function_apps) : a.zip_deploy_file == null])
    error_message = "zip_deploy_file is broken upstream for flex consumption apps (the publish poll 404s); push the package from outside the resource instead (az functionapp deployment source config-zip, see the complete example and the repo README)."
  }
}

# A keyless storage account cannot serve a key-based connection string, so connection-string
# storage auth on a keyless app fails at runtime; keep the identity default or flip keys on.
check "keyless_apps_use_identity_auth" {
  assert {
    condition = alltrue([
      for k, a in var.function_apps :
      a.storage_shared_access_key_enabled || local.storage_auth[k] != "StorageAccountConnectionString"
    ])
    error_message = "A keyless app cannot use StorageAccountConnectionString auth."
  }
}

# Bring-your-own identity means the module grants nothing on storage: the identity owner must
# hold the documented role set or the deploy and host both fail at create.
check "byo_identity_needs_caller_grants" {
  assert {
    condition = alltrue([
      for k, a in var.function_apps :
      a.create_user_assigned_identity || a.storage_container_endpoint != null || local.storage_auth[k] == "StorageAccountConnectionString"
    ])
    error_message = "One or more apps bring their own identity with module-managed storage: ensure that identity holds Storage Blob Data Owner/Contributor (and Queue/Table Contributor) on the storage account, or deploys and the host will fail."
  }
}
