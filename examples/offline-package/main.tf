# The egress-blocked pattern: the app never builds anything server-side. The pipeline's deploy
# stage builds the Python dependencies ON THE RUNNER (pip install --target
# .python_packages/lib/site-packages, the layout the Functions host loads), zips the vendored
# result, and pushes it with remote build disabled: build where the internet is, ship a
# byte-identical artifact. Mandatory when the app cannot reach PyPI (VNet-isolated), and faster
# to cold-start-ready everywhere else. Applied, deployed, verified, then destroyed in one CI run.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-004"
  func_name = "func-off-${var.short}-${var.loc}-${terraform.workspace}-004"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "flex-offline-package" }
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
    }
  }
}
