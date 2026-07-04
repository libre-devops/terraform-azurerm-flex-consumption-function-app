provider "azurerm" {
  features {
    resource_group {
      # App Insights auto-creates a Smart Detection action group inside the rg;
      # without this the destroy is blocked.
      prevent_deletion_if_contains_resources = false
    }
  }

  storage_use_azuread = true
}
