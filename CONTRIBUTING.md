# Contributing

## Prerequisites

Install the following tools before working on `provider-litellm`:

- Go 1.27
- Docker (with buildx)

All other tools (Terraform 1.5.7, kubectl, kind, helm, the Crossplane CLI,
chainsaw and uptest) are downloaded into `.cache/tools` by the Makefile.

## Upjet architecture

`provider-litellm` is an Upjet-based Crossplane provider. Upjet generates Crossplane managed resources and controllers from the upstream Terraform provider (`BerriAI/terraform-provider-litellm`), so most API surface changes flow through code generation and provider configuration rather than handwritten controllers.

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
make lint
```

### Track upstream Terraform provider changes

```bash
make generated-lst-check                      # config/generated.lst is up to date
make schema-diff OLD_PROVIDER_VERSION=1.97.0  # diff against an older provider release
make schema-version-diff                      # diff schema versions of generated resources
```

### Build and release

```bash
make build      # binaries, runtime image and the .xpkg package
make publish    # push the package to $(XPKG_REG_ORGS)
```

Releases are cut by pushing a `vX.Y.Z` tag (or via the `Auto Release` workflow);
the `Release` workflow then builds and pushes
`ghcr.io/corewire/provider-litellm:vX.Y.Z`.

## Agent skill: building an upjet provider

`.github/skills/upjet-provider/` documents the full reference architecture for an
upjet-based Crossplane provider (repository layout, build system, `config/`
patterns, generation pipeline, testing, and CI/schema-diff automation), derived
from `crossplane-contrib/provider-keycloak`. Point an AI agent at it when
extending this provider or bootstrapping a new one for another Terraform
provider.
