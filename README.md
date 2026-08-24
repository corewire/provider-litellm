# provider-litellm

`provider-litellm` is an upjet-based [Crossplane](https://crossplane.io/) provider that manages [LiteLLM](https://github.com/BerriAI/litellm) resources declaratively. Built on [Upjet](https://github.com/crossplane/upjet) using [BerriAI/terraform-provider-litellm](https://github.com/BerriAI/terraform-provider-litellm).

## Managed Resources

All managed resources are generated from
[`BerriAI/terraform-provider-litellm`](https://github.com/BerriAI/terraform-provider-litellm)
v1.98.0.

| API version | Kind | Description |
|-------------|------|-------------|
| `litellm.crossplane.io/v1alpha1` | `Model` | Model routing configuration (provider, API base, costs, rate limits) |
| `litellm.crossplane.io/v1alpha1` | `Team` | Team with budget and model access controls |
| `litellm.crossplane.io/v1alpha1` | `Organization` | Organization with budget and model access controls |
| `litellm.crossplane.io/v1alpha1` | `Key` | API key with budget, rate-limit and guardrail configuration |
| `litellm.crossplane.io/v1alpha1` | `Credential` | Stored provider credentials |
| `litellm.crossplane.io/v1alpha1` | `TeamMember` / `TeamMemberAdd` | Team membership management |
| `litellm.crossplane.io/v1alpha1` | `OrganizationMember` / `OrganizationMemberAdd` | Organization membership management |
| `litellm.crossplane.io/v1alpha1` | `McpServer` | Model Context Protocol server |
| `litellm.crossplane.io/v1alpha1` | `VectorStore` | Vector store configuration |

## Getting Started

### Install

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-litellm
spec:
  package: ghcr.io/corewire/provider-litellm:v0.1.0
```

### Configure

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: litellm-credentials
  namespace: crossplane-system
type: Opaque
stringData:
  credentials: |
    {
      "api_base": "http://your-litellm-server:4000",
      "api_key": "your-master-key"
    }
---
apiVersion: litellm.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: litellm-credentials
      key: credentials
```

Alternatively, use individual secret keys instead of JSON:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: litellm-credentials
  namespace: crossplane-system
stringData:
  api_base: "http://your-litellm-server:4000"
  api_key: "your-master-key"
```

### Supported credential fields

| Field | Required | Description |
|-------|----------|-------------|
| `api_base` | ✅ | Base URL of the LiteLLM proxy |
| `api_key` | ✅ | LiteLLM master key or virtual key |
| `insecure_skip_verify` | ❌ | Skip TLS verification (dev only) |

## Provider Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--debug` | `false` | Enable debug logging |
| `--sync` | `1h` | Controller manager sync period |
| `--poll` | `10m` | Drift check interval |
| `--max-reconcile-rate` | `10` | Global max reconciliations/s |
| `--max-concurrent-reconciles` | `5` | Max concurrent reconcile ops |
| `--enable-management-policies` | `true` | Enable Management Policies |
| `--leader-election` | `false` | Enable leader election |

## Development

### Prerequisites

- Go 1.27+
- Docker (with buildx) for building the runtime image and provider package
- [Tilt](https://tilt.dev/) for the local development loop
- Everything else (Terraform 1.5.7, kubectl, kind, helm, the Crossplane CLI,
  chainsaw and uptest) is downloaded into `.cache/tools` by the Makefile

### Local development with Tilt

Tilt provides a fast, hot-reloading local dev loop:
- rebuilds the provider binary on every Go source change
- loads the new image into the local kind cluster without a full registry push
- deploys Crossplane, the in-cluster LiteLLM instance, the `litellm-credentials`
  Secret, and the `ProviderConfig` automatically
- streams provider logs in the Tilt UI

```sh
# Start the local kind cluster and the Tilt dev environment
make tilt-up

# Open the Tilt UI
open http://localhost:10350

# Tear everything down when done
make tilt-down
```

To override defaults (image repo, LiteLLM master key, etc.), copy
`tilt-settings.yaml.example` to `tilt-settings.yaml` (git-ignored) and adjust
the values.

### Code generation

```sh
git submodule update --init --recursive
make generate
```

### Build & Test

```sh
make build              # binaries, runtime image and the .xpkg package
make test               # run unit tests
make lint               # run golangci-lint
make local-deploy       # build and install the provider into a local kind cluster
make e2e                # run the full chainsaw e2e suite (deploys LiteLLM in-cluster)
make generated-lst-check # verify config/generated.lst is up to date
make schema-diff OLD_PROVIDER_VERSION=1.97.0 # diff the Terraform provider schema
```

### Project structure

```
provider-litellm/
├── apis/
│   ├── v1beta1/         # ProviderConfig types; zz_*.go generated
│   └── <group>/v1alpha1/ # generated managed resource types
├── cmd/
│   ├── generator/       # Code generator entry point
│   └── provider/        # Controller manager entry point
├── config/              # Upjet provider + resource configuration
├── internal/
│   ├── clients/         # Credential extraction, Terraform setup
│   ├── controller/      # Controller setup (zz_setup.go generated)
│   ├── features/        # Feature flags
│   └── version/         # Version info
├── examples/            # Usage examples
├── examples-generated/  # Generated usage examples
├── cluster/
│   ├── images/          # Runtime image (distroless) build
│   └── test/            # E2E test infrastructure (Chainsaw)
├── package/             # Crossplane package metadata and generated CRDs
├── scripts/             # Schema diff and upstream release tooling
└── Makefile
```

## Architecture

Uses the **no-fork** (embedded) Upjet mode: the LiteLLM Terraform provider is
compiled directly into the Crossplane provider binary — no separate Terraform
CLI process, faster reconciliation, simpler deployment.

## License

Apache License 2.0
