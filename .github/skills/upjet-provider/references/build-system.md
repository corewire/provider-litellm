# Build system

The Makefile is layered on the `crossplane/build` submodule
(`git submodule add https://github.com/crossplane/build build`, branch `master`),
which supplies `common.mk`, `output.mk`, `golang.mk`, `k8s_tools.mk`,
`imagelight.mk`, `xpkg.mk`, `local.xpkg.mk`, `controlplane.mk`.

## Variables

```makefile
PROJECT_NAME ?= provider-<name>
PROJECT_REPO ?= github.com/<ORG>/$(PROJECT_NAME)

export TERRAFORM_VERSION ?= 1.5.7   # MUST stay < 1.6 (BSL)
TERRAFORM_VERSION_VALID := $(shell [ "$(TERRAFORM_VERSION)" = "`printf "$(TERRAFORM_VERSION)\n1.6" | sort -V | head -n1`" ] && echo 1 || echo 0)

export TERRAFORM_PROVIDER_SOURCE  ?= <TF_SOURCE>
export TERRAFORM_PROVIDER_REPO    ?= <TF_REPO>
# renovate: datasource=github-releases depName=<owner>/terraform-provider-<name>
export TERRAFORM_PROVIDER_VERSION ?= x.y.z
export TERRAFORM_PROVIDER_DOWNLOAD_NAME ?= terraform-provider-<name>
export TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX ?= ${TERRAFORM_PROVIDER_REPO}/releases/download/v$(TERRAFORM_PROVIDER_VERSION)
export TERRAFORM_NATIVE_PROVIDER_BINARY ?= terraform-provider-<name>_v$(TERRAFORM_PROVIDER_VERSION)
export TERRAFORM_DOCS_PATH        ?= docs/resources
export TERRAFORM_FILE_MIRROR      ?= .terraform.d/plugins
export TERRAFORM_FILE_MIRROR_REPO ?= ${TERRAFORM_FILE_MIRROR}/registry.terraform.io

PLATFORMS ?= linux_amd64 linux_arm64
GO_STATIC_PACKAGES = $(GO_PROJECT)/cmd/provider $(GO_PROJECT)/cmd/generator
GO_LDFLAGS += -X $(GO_PROJECT)/internal/version.Version=$(VERSION)
GO_SUBDIRS += cmd internal apis config
TERRAFORM_PROVIDER_SCHEMA := config/schema.json
```

Pin the toolchain explicitly so CI and local runs agree: `GO_REQUIRED_VERSION`,
`GOLANGCILINT_VERSION`, `KUBECTL_VERSION`, `KIND_VERSION`, `UP_VERSION`,
`UPTEST_VERSION`, `CHAINSAW_VERSION`, `CROSSPLANE_VERSION`, `CROSSPLANE_CLI_VERSION`.

## Schema acquisition (`config/schema.json`)

Terraform CLI is used **only at generation time** to dump the provider schema:

1. `download-tf-provider-platforms` → for each entry in `PLATFORMS`, download
   `${DOWNLOAD_URL_PREFIX}/${DOWNLOAD_NAME}_${VERSION}_${PLATFORM}.zip` into a
   filesystem mirror at `$(WORK_DIR)/terraform/$(TERRAFORM_FILE_MIRROR_REPO)/...`
   and unzip it. Use `curl --retry 5 --retry-delay 5 --retry-all-errors`.
2. Write `main.tf.json` with `required_providers` pinned to
   `<TF_SOURCE>@$(TERRAFORM_PROVIDER_VERSION)` and `config.tfrc` with a
   `provider_installation { filesystem_mirror { ... include = ["*/*/*"] } }` block.
3. `TF_CLI_CONFIG_FILE=... terraform init -no-color` then
   `terraform providers schema -json=true > config/schema.json`.

Hook it into generation with `generate.init: $(TERRAFORM_PROVIDER_SCHEMA) pull-docs`.

## Docs acquisition (`pull-docs`)

Sparse, shallow, blobless clone of the TF provider repo at the pinned tag, checking
out only `$(TERRAFORM_DOCS_PATH)`:

```makefile
git clone -c advice.detachedHead=false --depth 1 --filter=blob:none \
  --branch "v$(TERRAFORM_PROVIDER_VERSION)" --sparse "$(TERRAFORM_PROVIDER_REPO)" \
  "$(WORK_DIR)/$(TERRAFORM_PROVIDER_SOURCE)"
git -C "$(WORK_DIR)/$(TERRAFORM_PROVIDER_SOURCE)" sparse-checkout set "$(TERRAFORM_DOCS_PATH)"
```

The scraper in `generate/generate.go` reads from `../.work/${TERRAFORM_PROVIDER_SOURCE}/${TERRAFORM_DOCS_PATH}`.

## Generation hooks

```makefile
generate.init: $(TERRAFORM_PROVIDER_SCHEMA) pull-docs
generate.done: generated-lst        # + e2e-index, docs-gen if you have them
```

`generated-lst` / `generated-lst-check` run `go run ./cmd/generatedlist [--check] config/generated.lst`.

## Local development and e2e

```makefile
controlplane.up:   # kind create cluster + helm install crossplane (pinned chart)
local-deploy: build controlplane.up local.xpkg.deploy.provider.$(PROJECT_NAME)
uptest:            # uptest e2e "$(UPTEST_EXAMPLE_LIST)" --setup-script=cluster/test/setup.sh \
                   #   --default-conditions="Test" --default-timeout=2400s
e2e: local-deploy uptest
```

`UPTEST_EXAMPLE_LIST := $(shell grep -v '^\#' cluster/test/cases.txt | paste -sd ',' -)`.

## Schema diffing

- `schema-version-diff` (CI): read `TERRAFORM_PROVIDER_VERSION` and `config/schema.json`
  from `${GITHUB_BASE_REF}` via `git cat-file -p`, then run
  `./scripts/version_diff.py config/generated.lst <old> config/schema.json`.
- `schema-diff OLD_PROVIDER_VERSION=x.y.z` (manual): download the old provider
  binary for the host platform, dump its schema with terraform, diff against the
  current one.
- `crddiff` (CI, optional but recommended): `uptest crddiff revision` against the base
  branch CRDs to catch breaking CRD changes; allow overriding with
  `CRDDIFF_ALLOW_BREAKING=true` for intentional major bumps.

## Misc targets

`submodules`, `go.cachedir` (cache key for GitHub Actions), `cobertura` (coverage
report excluding `zz_*`), `run` (out-of-cluster provider), `test.race` for
concurrency-sensitive packages.
