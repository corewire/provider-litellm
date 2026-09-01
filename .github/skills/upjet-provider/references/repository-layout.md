# Repository layout

The canonical layout, derived from `crossplane-contrib/provider-keycloak`. Files marked
**(gen)** are produced by `make generate` and must never be hand-edited.

```
provider-<name>/
├── .github/
│   ├── workflows/            # ci, auto-release, tag, provider-release-check, schema-diff-issues
│   ├── renovate.json         # dependency automation (pin the TF provider carefully)
│   └── CODEOWNERS
├── .golangci.yml
├── .gitmodules               # build/ -> https://github.com/crossplane/build (branch master)
├── Makefile                  # see references/build-system.md
├── Dockerfile                # distroless/static, single Go binary, USER 65532
├── apis/
│   ├── v1beta1/              # hand-written ProviderConfig / ProviderConfigUsage / StoreConfig
│   ├── <group>/v1beta1/      # (gen) zz_<resource>_types.go, zz_generated.*.go
│   └── zz_register.go        # (gen)
├── cmd/
│   ├── provider/main.go      # controller-manager entrypoint (+ (gen) zz_*.go)
│   ├── generator/main.go     # upjet pipeline runner
│   ├── generatedlist/main.go # writes/validates config/generated.lst
│   └── crdconversion/main.go # optional: enables conversion webhooks on multi-version CRDs
├── cluster/
│   ├── images/provider-<name>/  # Dockerfile + image Makefile (if not at repo root)
│   └── test/                 # setup.sh, cases*.txt, chainsaw-config.yaml, conversion tests
├── config/
│   ├── provider.go           # GetProvider (+ GetProviderNamespaced)
│   ├── external_name.go      # ExternalNameConfigs map — source of truth
│   ├── schema.json           # committed TF provider schema (embedded)
│   ├── provider-metadata.yaml# committed scraped TF docs (embedded)
│   ├── generated.lst         # (gen) sorted list of exposed TF resources
│   ├── common/               # shared extractors/helpers
│   └── <group>/config.go     # per-group Configure(p *ujconfig.Provider)
├── examples/                 # hand-written example manifests (used by e2e)
├── examples-generated/       # (gen)
├── generate/generate.go      # //go:generate pipeline (build tag `generate`)
├── hack/boilerplate.go.txt   # header injected into generated files
├── internal/
│   ├── clients/<name>.go     # TerraformSetupBuilder + credential extraction (+ tests)
│   ├── controller/           # (gen) zz_setup.go + per-resource controllers
│   ├── features/features.go  # feature.Flag constants
│   └── version/version.go    # ldflags-injected version
├── package/
│   ├── crossplane.yaml       # meta.pkg.crossplane.io/v1 Provider, capabilities: [safe-start]
│   └── crds/                 # (gen)
└── scripts/
    ├── version_diff.py       # two-schema diff (new/removed resources, schema versions, attrs)
    ├── schema_diff_issues.py # schema.json vs generated.lst -> one issue per unexposed resource
    ├── check_provider_release.py # upstream release tracking: --mode issue | --mode bump
    └── e2e_dag.py            # optional: DAG-based targeted e2e selection
```

## Hand-written vs generated

Hand-written, and therefore the only things you actually author:

- `apis/v1beta1/*` (ProviderConfig types, `groupversion_info.go`, register)
- `config/**` except `generated.lst`, `schema.json`, `provider-metadata.yaml`
- `cmd/**/main.go`
- `internal/clients/**`, `internal/features/**`, `internal/version/**`
- `generate/generate.go`, `hack/boilerplate.go.txt`
- `Makefile`, `Dockerfile`, `.github/**`, `scripts/**`, `cluster/**`, `examples/**`
- docs: `README.md`, `CONTRIBUTING.md`, and a repo-local `SKILL.md` / `AGENTS.md`

## `apis/v1beta1` — ProviderConfig

Provide `ProviderConfig`, `ProviderConfigUsage`, `ProviderConfigList`,
`ProviderConfigUsageList` and (optionally) `StoreConfig`. With
crossplane-runtime **v2**:

- `ProviderConfigUsage` embeds `xpv1.ProviderConfigUsage` **inline** — there is no
  `ProviderConfigUsageSpec` type.
- `GetProviderConfigReference()` lives on `resource.ModernManaged` /
  `resource.LegacyManaged`, not on `resource.Managed`.

## Namespaced resources (optional but recommended)

provider-keycloak generates two complete API surfaces:

- cluster-scoped under `apis/cluster/...`, root group `<name>.crossplane.io`
- namespaced under `apis/namespaced/...`, root group `<name>.m.crossplane.io`

This requires `config.GetProviderNamespaced()` (same as `GetProvider` plus
`ujconfig.WithShortName("<name>")` and the `.m.` root group) and
`pipeline.Run(provider, providerNamespaced, rootDir)` in `cmd/generator/main.go`.
If you only want cluster scope, pass `nil` as the second argument and keep
`apis/<group>/...` flat.

Decide this **before** the first `make generate`: switching later renames every
API group and is a breaking change for users.
