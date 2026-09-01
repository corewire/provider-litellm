# Troubleshooting

Pitfalls that bite when standing up an upjet v2 provider, and how to resolve them.

## Compile-time

**`mg.GetProviderConfigReference undefined`**
crossplane-runtime v2 moved `GetProviderConfigReference()` off `resource.Managed`.
Type-assert to `resource.ModernManaged` (namespaced/modern MRs) or
`resource.LegacyManaged` (cluster-scoped legacy MRs) in the setup function.

**`ProviderConfigUsageSpec` does not exist**
In crossplane-runtime v2 `ProviderConfigUsage` embeds `xpv1.ProviderConfigUsage`
inline; there is no `Spec` wrapper. Copy the type from an up-to-date v2 provider.

**`*schema.Provider does not implement tfprotov*.ProviderServer` /
missing `GenerateResourceConfig`**
`terraform-plugin-go` v0.31.0 added methods to `ProviderServer`. If the upstream
Terraform provider pulls that version, `terraform-plugin-framework` must be new
enough to implement them (≥ v1.19.0). Pin it explicitly in `go.mod`. In general:
whenever the SDK, framework, plugin-go and plugin-mux versions disagree, align them
to the set the upstream provider itself uses.

**Go toolchain too old**
upjet v2 sets a Go floor (currently 1.26.x). Set `go`/`toolchain` in `go.mod` and
`GO_REQUIRED_VERSION` in the Makefile to matching values, and use the same version
in CI.

**Import cycles in `zz_generated.resolvers.go`**
That is exactly what `upjet/v2/cmd/resolver -s -a <module>/internal/apis` fixes —
make sure that stage is present and re-run `make generate`.

**Broken transitive test dependency**
Occasionally a dependency ships an unbuildable test import (e.g. `go-openapi/swag`
v0.25.4). Pin the nearest good version with an explicit `require` and note why.

## Generation

**`there should exactly be 1 provider schema`**
`config/schema.json` was produced with more than one provider in `required_providers`,
or the file is stale/empty. Delete it and re-run `make generate`.

**Scraper produces empty metadata**
`TERRAFORM_DOCS_PATH` is wrong for that repo (`docs/resources` vs `website/docs/r`),
or `pull-docs` sparse-checkout failed. Check `.work/<TF_SOURCE>/`.

**Resource does not appear as a CRD**
It must be in `ExternalNameConfigs` *and* in the matching include list
(`WithTerraformPluginSDKIncludeList` for SDKv2, `WithTerraformPluginFrameworkIncludeList`
for framework resources). Regex anchors matter: use `"<name>_thing$"`.

**Type name collisions / ugly Kinds**
Use `r.Kind` and `r.OverrideFieldNames` in the group configurator.

**`make generate` produces a huge unrelated diff**
The upstream provider version or upjet version changed. Review with
`make schema-version-diff` before accepting it.

## Runtime

**Resource never becomes `Ready`, `Observe` keeps recreating it**
The external-name strategy is wrong. If the API assigns the ID, use
`IdentifierFromProvider`; if the ID is a composite, use
`TemplatedStringAsIdentifier`.

**Endless diff / late-init flapping**
The API returns a server-side default the CRD does not model. Add the field to
`r.LateInitializer.IgnoredFields`, or mark it computed in the schema override.

**`terraform init` errors at runtime**
No-fork providers must construct the workspace store with
`terraform.WithDisableInit(true)` and pass the embedded provider via
`ujconfig.WithTerraformProvider(p)`.

**Upstream API rate limiting / session exhaustion**
Add `PollJitter`, lower `--max-reconcile-rate`, and cache/pool the configured
client (see `references/clients.md`).

**Provider crash-loops when a CRD is missing**
Implement safe-start gating, and consider wrapping the manager so one failing
controller cannot terminate the process.

## Licensing

Terraform ≥ 1.6 is BSL-licensed. Keep `TERRAFORM_VERSION < 1.6` and keep the
Makefile guard that fails the build otherwise.
