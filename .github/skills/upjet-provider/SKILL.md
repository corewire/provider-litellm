---
name: upjet-provider
description: Build a production-grade upjet v2 Crossplane provider from any Terraform provider, following the crossplane-contrib/provider-keycloak reference architecture — repo scaffold, code generation pipeline, external-name/reference configuration, CI, e2e tests, schema-diff and upstream-release automation. Use when creating a new Crossplane provider, porting a Terraform provider to Crossplane, or auditing an existing upjet provider for missing pieces.
---

# The Perfect Upjet Provider

This skill describes end-to-end how to build a Crossplane provider from a Terraform
provider using [upjet](https://github.com/crossplane/upjet) v2, matching the
architecture of [`crossplane-contrib/provider-keycloak`](https://github.com/crossplane-contrib/provider-keycloak)
— the reference implementation this skill is derived from.

Throughout, substitute:

| Placeholder | Example (keycloak) | Example (litellm) |
|---|---|---|
| `<name>` | `keycloak` | `litellm` |
| `<ORG>` | `crossplane-contrib` | `corewire` |
| `<TF_SOURCE>` | `keycloak/keycloak` | `BerriAI/litellm` |
| `<TF_REPO>` | `https://github.com/keycloak/terraform-provider-keycloak` | `https://github.com/BerriAI/terraform-provider-litellm` |
| `<ROOT_GROUP>` | `keycloak.crossplane.io` | `litellm.crossplane.io` |

## Before you start — inputs you must collect

1. **Terraform provider repo + latest release tag** (`<TF_REPO>`, `v<TERRAFORM_PROVIDER_VERSION>`).
2. **Registry source address** (`<TF_SOURCE>`, as used in `required_providers`).
3. **Whether the provider is SDKv2 (`helper/schema`), plugin-framework, or muxed.**
   This decides `WithTerraformPluginSDKIncludeList` vs `WithTerraformPluginFrameworkIncludeList`.
4. **The exported provider constructor** (e.g. `provider.KeycloakProvider(nil)`,
   `litellm.Provider()`) — needed for the no-fork runtime path.
5. **Docs path inside the TF repo** (`docs/resources`, sometimes `website/docs/r`).
6. **Auth model** — which provider-config attributes are required, which are secret.
7. **Release asset naming** — `<name>_<version>_<os>_<arch>.zip`, needed to fetch the
   schema for the supported `PLATFORMS`.

Do not guess these. Fetch the upstream repo and read `main.go` / `docs/` first.

## Build order

Work in this order; each step is verifiable on its own.

1. **Scaffold the repository** → `references/repository-layout.md`
2. **Makefile + build submodule** → `references/build-system.md`
3. **`config/` — schema, metadata, external names, per-group config** → `references/config-patterns.md`
4. **`internal/clients/<name>.go` — the `terraform.SetupFn`** → `references/clients.md`
5. **`cmd/provider/main.go` — the controller manager** → `references/provider-main.md`
6. **`generate/generate.go` — the generation pipeline**, then run `make generate` → `references/generation-pipeline.md`
7. **Examples + e2e (chainsaw/uptest)** → `references/testing.md`
8. **CI, release, and upstream-tracking automation** → `references/automation.md`
9. **Docs (`README`, `CONTRIBUTING`, repo-local `SKILL.md`/`AGENTS.md`)**

A provider is only "complete" when every item in `references/checklist.md` is ticked.

## Non-negotiable rules

- **Terraform CLI version must stay `< 1.6`.** Terraform 1.6+ is BSL-licensed and
  cannot be used in an Apache-2.0 project. The Makefile must *fail* on a higher
  version (`check-terraform-version`).
- **No-fork only.** Embed the Terraform provider as a Go dependency and pass it via
  `ujconfig.WithTerraformProvider(p)`. Never ship a `terraform` binary in the image
  and never shell out to it at runtime. The runtime image is `distroless/static`
  with a single Go binary.
- **`config/schema.json` and `config/provider-metadata.yaml` are committed.**
  They are `//go:embed`-ed, so generation and runtime never need network access.
- **`config/external_name.go` is the single source of truth** for which Terraform
  resources are exposed. `config/generated.lst` is derived from it by
  `cmd/generatedlist` and verified in CI (`make generated-lst-check`).
- **Never hand-edit generated output**: `apis/**/zz_*.go`, `internal/controller/**/zz_*.go`,
  `package/crds/`, `examples-generated/`. Change `config/` and re-run `make generate`.
- **CI must run `make generate` and fail on a dirty tree** (`check-diff`). This is
  what keeps generated code honest.
- **Every exposed managed resource needs an e2e example** and must be listed in a
  `cluster/test/cases*.txt` file; enforce it with a coverage check.
- **Bumping the upstream Terraform provider is never "just a version bump".**
  Gate it on `make schema-version-diff` (state-schema version changes) and
  `make crddiff` (breaking CRD changes).

## Quick reference — the commands every provider must support

```bash
make submodules              # init the crossplane/build submodule (first run)
make generate                # schema -> docs -> types -> CRDs -> controllers -> lists
make build                   # build the provider binary + xpkg
make test                    # unit tests
make lint                    # golangci-lint
make local-deploy            # kind + crossplane + locally built provider
make e2e                     # local-deploy + uptest/chainsaw suite
make schema-version-diff     # TF state-schema drift vs base branch (CI)
make schema-diff OLD_PROVIDER_VERSION=x.y.z   # manual two-version schema diff
make crddiff                 # breaking CRD change detection (CI)
make generated-lst-check     # generated.lst is in sync with external_name.go
```

Always run `make lint` (and `make generate`) before committing Go changes.

## Reference files

| File | Read it when |
|---|---|
| `references/repository-layout.md` | Creating the repo skeleton; what every file/dir is for |
| `references/build-system.md` | Writing the Makefile: schema fetch, docs pull, platforms, tool pinning |
| `references/config-patterns.md` | Choosing external names, references, groups, kinds, sensitive fields |
| `references/clients.md` | Writing `TerraformSetupBuilder`, credential handling, session/client pooling |
| `references/provider-main.md` | Controller-manager wiring, flags, feature gates, safe-start, webhooks |
| `references/generation-pipeline.md` | `generate/generate.go` directives and what each stage produces |
| `references/testing.md` | Examples, uptest/chainsaw, e2e case lists, coverage gates |
| `references/automation.md` | CI jobs, release workflows, schema-diff issues, upstream release checks |
| `references/troubleshooting.md` | Known upjet v2 / crossplane-runtime v2 compile and runtime pitfalls |
| `references/checklist.md` | Final completeness checklist for a "perfect" provider |
