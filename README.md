# provider-litellm

`provider-litellm` is an upjet-based [Crossplane](https://crossplane.io/) provider that manages [LiteLLM](https://github.com/BerriAI/litellm) resources declaratively. Built on [Upjet](https://github.com/crossplane/upjet) using [BerriAI/terraform-provider-litellm](https://github.com/BerriAI/terraform-provider-litellm).

## Managed Resources

| Resource | Description |
|----------|-------------|
| `Model` | Model routing configuration (provider, API base, costs, rate limits) |
| `Team` | Team with budget and model access controls |
| `TeamMember` / `TeamMemberAdd` | Team membership management |
| `Organization` / `OrganizationMember` | Organization and member management |
| `Key` | API key with budget, rate-limit and guardrail configuration |
| `Credential` | Stored provider credentials |
| `MCPServer` | Model Context Protocol server |
| `VectorStore` | Vector store configuration |

## Getting Started

### Install

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-litellm
spec:
  package: xpkg.upbound.io/corewire/provider-litellm:latest
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

- Go 1.26+
- Terraform ≤ 1.5.7 (BSL-free)
- kubectl, kind, up CLI, Crossplane CLI

### Code generation

```sh
git submodule update --init --recursive
make generate
```

### Build & Test

```sh
make build          # compile provider binary
make test           # run unit tests
make e2e            # run e2e tests (requires LITELLM_API_BASE + LITELLM_API_KEY)
golangci-lint run   # lint
```

### Project structure

```
provider-litellm/
├── apis/v1beta1/        # ProviderConfig types; zz_*.go generated
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
├── cluster/test/        # E2E test infrastructure (Chainsaw)
├── package/             # Crossplane package metadata
├── Dockerfile
└── Makefile
```

## Architecture

Uses the **no-fork** (embedded) Upjet mode: the LiteLLM Terraform provider is
compiled directly into the Crossplane provider binary — no separate Terraform
CLI process, faster reconciliation, simpler deployment.

## License

Apache License 2.0
