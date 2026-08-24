# Completeness checklist

A provider is "perfect" (provider-keycloak-grade) when every box below is ticked.

## Scaffold

- [ ] `build/` submodule wired; `make submodules` works from a clean clone
- [ ] `Makefile` with pinned `TERRAFORM_VERSION` (< 1.6) and a `check-terraform-version` guard
- [ ] `TERRAFORM_PROVIDER_*` variables set, with a `# renovate:` comment on the version
- [ ] `PLATFORMS` covers every platform you publish (`linux_amd64 linux_arm64`)
- [ ] `Dockerfile` on digest-pinned `gcr.io/distroless/static`, `USER 65532`, no terraform binary
- [ ] `package/crossplane.yaml` with `capabilities: [safe-start]`
- [ ] `.golangci.yml`, `CODEOWNERS`, `.github/renovate.json`, `LICENSE`

## Configuration

- [ ] `config/schema.json` and `config/provider-metadata.yaml` committed and embedded
- [ ] `config/external_name.go` covers every resource you intend to expose
- [ ] Include lists match the plugin type (SDKv2 vs framework)
- [ ] `KnownReferencers()` wires the recurring foreign-key fields
- [ ] One `config/<group>/config.go` per API group, registered in `GetProvider`
- [ ] Sensitive fields marked `Sensitive` **before** the first release
- [ ] `config/generated.lst` generated and checked in CI

## Code

- [ ] `internal/clients/<name>.go` with `TerraformSetupBuilder` + unit tests
- [ ] Required provider attributes validated with explicit errors; credentials never logged
- [ ] `cmd/provider/main.go` with metrics, feature gates, `PollJitter`, leader election
- [ ] `cmd/generator/main.go`, `cmd/generatedlist/main.go` (+ `cmd/crdconversion` if multi-version)
- [ ] `internal/features`, `internal/version`
- [ ] `apis/v1beta1` ProviderConfig types (crossplane-runtime v2 shapes)

## Generation

- [ ] `generate/generate.go` with all stages: clean → scrape → generator → controller-gen → angryjet → resolver
- [ ] `generate.init` fetches schema and docs; `generate.done` refreshes derived lists
- [ ] `make generate` is idempotent — a second run leaves the tree clean

## Testing

- [ ] Unit tests for all hand-written packages; `-race` where concurrency matters
- [ ] `examples/` manifest for every exposed resource
- [ ] `cluster/test/setup.sh` + `cases.txt`; `make e2e` green against a real backend
- [ ] Coverage gate: no example missing, no orphan example
- [ ] Conversion tests if CRDs are multi-version

## Automation

- [ ] `ci.yml` with detect-noop, lint, check-diff, unit-tests, build, e2e
- [ ] `schema-version-diff` and `crddiff` jobs
- [ ] `auto-release` + `tag` workflows
- [ ] `schema-diff-issues` workflow + `scripts/schema_diff_issues.py`
- [ ] `provider-release-check` workflow + `scripts/check_provider_release.py`
- [ ] `scripts/version_diff.py`
- [ ] Scheduled workflows dry-run on PRs and are path-filtered

## Documentation

- [ ] `README.md`: install, ProviderConfig, a worked example, dev quickstart
- [ ] `CONTRIBUTING.md`: how to expose a new resource (edit `external_name.go`,
      add a group config, `make generate`, add an example, add to `cases.txt`)
- [ ] Repo-local `SKILL.md` / `AGENTS.md` for AI agents, listing the generated
      paths that must never be hand-edited
- [ ] Every deviation from this checklist documented with its reason
