# Contributing

## Prerequisites

Install the following tools before working on `provider-litellm`:

- Go 1.24
- Terraform
- kubectl
- kind
- Upbound CLI (`up`)

## Upjet architecture

`provider-litellm` is an Upjet-based Crossplane provider. Upjet generates Crossplane managed resources and controllers from the upstream Terraform provider (`BerriAI/litellm`), so most API surface changes flow through code generation and provider configuration rather than handwritten controllers.

## Common development commands

### Generate code

```bash
make generate
```

### Run tests

```bash
make test
```

### Run end-to-end tests

Make sure your local cluster is available and the LiteLLM credentials are exported first.

```bash
export LITELLM_API_BASE="https://your-litellm-endpoint"
export LITELLM_API_KEY="your-api-key"
./cluster/test/setup.sh
make e2e
```

### Run linting

```bash
golangci-lint run
```

## Agent skill: building an upjet provider

`.github/skills/upjet-provider/` documents the full reference architecture for an
upjet-based Crossplane provider (repository layout, build system, `config/`
patterns, generation pipeline, testing, and CI/schema-diff automation), derived
from `crossplane-contrib/provider-keycloak`. Point an AI agent at it when
extending this provider or bootstrapping a new one for another Terraform
provider.
