<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform Azure Flex Consumption Function App

Azure Functions Flex Consumption done properly: keyless identity auth wired end to end, plans and
storage that flex with you, and a deploy story that actually works.

[![CI](https://github.com/libre-devops/terraform-azurerm-flex-consumption-function-app/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azurerm-flex-consumption-function-app/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azurerm-flex-consumption-function-app?sort=semver&label=release)](https://github.com/libre-devops/terraform-azurerm-flex-consumption-function-app/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azurerm-flex-consumption-function-app)](./LICENSE)

---

## Overview

Flex consumption is a massive resource with sharp edges, and this module took the live bruises so
you do not have to. Fast to get going: an entry with nothing but a runtime gets a dedicated FC1
plan, keyless storage with a deployment container, a user-assigned identity granted the full
documented role set BEFORE the app exists (system-assigned plus deploy-during-create is a
bootstrap deadlock), and the identity host storage settings wired automatically. Flexible when it
matters: every one of those defaults has an explicit override.

- **Keyless by default, correctly.** `shared_access_key_enabled = false` with the complete
  documented recipe: Storage Blob Data Owner (the host's secrets store) plus Blob, Queue, and
  Table Contributor for the identity, and `AzureWebJobsStorage__accountName` /
  `__credential = managedidentity` / `__clientId` app settings. One documented limitation,
  verified live: the host and function keys API is unavailable keyless, so use anonymous or AAD
  (Easy Auth) trigger auth, or flip keys on (the connection-string opt-out is first class).
- **Plans as a map, not a straitjacket.** Multiple apps can share a plan, `sku_name` is not
  welded to FC1, and `app_service_environment_id` is there for ASE placement. Apps that reference
  no plan get a dedicated FC1 plan automatically.
- **Storage in three shapes.** Created (default, secure defaults throughout), bring-your-own
  account by id (the module still builds the container and still grants the roles, because it has
  the scope), or a raw container endpoint escape hatch where the caller owns all wiring.
- **A deploy story that works today.** The provider's `zip_deploy_file` publish path is broken
  upstream for flex (its status poll 404s on healthy apps), and an ARM-native pull deploy cannot
  work against keyless storage (one-deploy fetches `packageUri` anonymously; verified live). The
  supported pattern is pushing the package with one-deploy from outside the resource, and the
  complete example shows it end to end: a real FastAPI app zipped by Terraform and pushed with
  `az functionapp deployment source config-zip`, keyed on the package hash, verified by curling
  the endpoint. `zip_deploy_file` stays as a passthrough for when upstream fixes it (a check
  steers you away meanwhile).
- **Application Insights, AAD-ingestion ready.** Pass the connection string and the AI resource
  id and the module wires the app setting, the AAD ingestion auth string, and the Monitoring
  Metrics Publisher grant.
- **The full resource surface.** Both auth_settings trees, site_config with CORS and IP
  restrictions, always-ready instances, sticky settings, connection strings, client certificates,
  VNet integration, and plan-time enforcement of the rules ARM only tells you about at apply
  (storage auth pairings, the flex instance memory sizes, CORS wildcard versus credentials).

Requires Terraform >= 1.9 and azurerm >= 4.0.

## Usage

```hcl
module "flex_function_app" {
  source  = "libre-devops/flex-consumption-function-app/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids["rg-ldo-uks-prd-001"]
  location          = "uksouth"
  tags              = module.tags.tags

  function_apps = {
    "func-api-ldo-uks-prd-001" = {
      runtime_name    = "python"
      runtime_version = "3.12"

      app_insights_connection_string = module.application_insights.connection_strings["appi-ldo-uks-prd-001"]
      app_insights_id                = module.application_insights.ids["appi-ldo-uks-prd-001"]
    }
  }
}
```

## Examples

- [`examples/minimal`](./examples/minimal) - one entry, nothing but a runtime: the whole secure
  stack arrives by default.
- [`examples/complete`](./examples/complete) - the full infrastructure surface: a shared plan
  hosting two apps (keyless identity auth and the keys-on opt-out side by side), Application
  Insights with AAD ingestion, scale tuning, and site_config; its FastAPI package deploys in the
  pipeline's deploy stage.
- [`examples/keyless`](./examples/keyless) - the total-automated-keyless-deployment showcase: no
  keys, no SAS, anywhere.
- [`examples/offline-package`](./examples/offline-package) - the vendored-wheels pattern for
  egress-blocked apps: pip installs into `.python_packages/lib/site-packages` on the runner, the
  package ships byte-identical, nothing builds server-side.
- [`examples/powershell`](./examples/powershell) - the PowerShell worker on the same secure stack
  (`run.ps1` + `function.json`, no build step, an empty `requirements.psd1` so the app needs no
  gallery access at runtime).

## Developing

Local work needs **PowerShell 7+** and **[`just`](https://github.com/casey/just)**, because the recipes
wrap the [LibreDevOpsHelpers](https://www.powershellgallery.com/packages/LibreDevOpsHelpers)
PowerShell module (the same engine the `libre-devops/terraform-azure` action runs in CI). Install
just with `brew install just`, or `uv tool add rust-just` then `uv run just <recipe>`.

Run `just` to list recipes: `just update-ldo-pwsh` (install or force-update LibreDevOpsHelpers from
PSGallery), `just validate`, `just scan` (Trivy only), `just pwsh-analyze` (PSScriptAnalyzer only),
`just plan`, `just apply`, `just destroy`, `just e2e`, `just test`, and `just docs` (the
plan/apply/destroy recipes mirror the action, including the storage firewall dance; `just e2e`
applies an example then always destroys it, defaulting to `minimal`, so nothing is left running).
Releasing is also `just`:
`just increment-release [patch|minor|major]` bumps, tags, and publishes a GitHub release, and the
Terraform Registry picks up the tag.

## Security scan exceptions

This module is scanned with [Trivy](https://github.com/aquasecurity/trivy); HIGH and CRITICAL
findings fail the build. Any waiver is a deliberate, reviewed decision, never a way to quiet a
finding that should be fixed. Waivers live in a `.trivyignore.yaml` (the machine-applied source of
truth, passed to Trivy with `--ignorefile`) and are mirrored in a table here so the reason is
auditable.

| ID | Scope | Reason |
| --- | --- | --- |
| AVD-AZU-0012 (storage network rules) | module-created storage accounts | Not fixable with IP rules, proven live: default-Deny with the app's own possible outbound IPs allow-listed 403s the deployment service and 503s the running host, because flex reaches storage from platform ranges. The working lockdown is VNet integration plus service or private endpoints, expressed through the per-app `storage_network_rules` input. |
| AVD-AZU-0060 (customer-managed keys) | module-created storage accounts | Deliberate non-goal for deployment package storage; platform-managed keys plus default infrastructure (double) encryption are the accepted posture. |
| AVD-AZU-0057 (storage analytics logging) | module-created storage accounts | Superseded by diagnostic settings, which belong to the caller's observability topology (the diagnostic-settings module). |

## Reference

The Requirements, Providers, Inputs, Outputs, and Resources below are generated by `terraform-docs`.
