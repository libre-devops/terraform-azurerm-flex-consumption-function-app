# The total-automated-keyless-deployment showcase: everything in this stack is keyless end to end.
# The app's storage has shared keys DISABLED (the module default), the host and the deployment
# service authenticate with the module-created user-assigned identity, and the FastAPI package in
# app/ is pushed by this repo's dedicated CI deploy stage using a FRESH OIDC login (push-bytes
# needs a live AAD token, and tokens minted at job start expire before a flex apply finishes; a
# dependent stage gets its own). No storage keys, no SAS, anywhere. Applied, deployed, verified,
# then destroyed in one CI run.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-003"
  func_name = "func-kl-${var.short}-${var.loc}-${terraform.workspace}-003"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "flex-keyless-showcase" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "flex_function_app" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  function_apps = {
    (local.func_name) = {
      runtime_name    = "python"
      runtime_version = "3.12"
      # Everything else is the keyless default: shared keys off, identity-authenticated storage,
      # the documented role set granted before the app, host storage settings wired.
    }
  }
}
