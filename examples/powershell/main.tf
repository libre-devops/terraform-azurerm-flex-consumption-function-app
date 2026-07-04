# The PowerShell runtime on flex consumption: the same secure stack (keyless identity-auth
# storage, dedicated FC1 plan), a different worker. PowerShell functions need no build step at
# all; the app/ package ships run.ps1 + function.json as-is, and requirements.psd1 stays empty so
# the app needs no gallery access at runtime. Applied, deployed, verified, then destroyed in one
# CI run.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-005"
  func_name = "func-ps-${var.short}-${var.loc}-${terraform.workspace}-005"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "flex-powershell" }
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
      runtime_name    = "powershell"
      runtime_version = "7.4"
    }
  }
}
