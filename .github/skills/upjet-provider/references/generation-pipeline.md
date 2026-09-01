# Generation pipeline

`generate/generate.go` carries the build tag `generate` and is a pure list of
`//go:generate` directives, executed by `make generate` (which first runs
`generate.init`: schema dump + docs pull).

## Stages, in order

```go
//go:build generate
// +build generate

// 1. Clean previous output
//go:generate rm -rf ../package/crds
//go:generate bash -c "find ../apis \\( -iname 'zz_generated.conversion_hubs.go' -o -iname 'zz_generated.conversion_spokes.go' -o -iname 'zz_generated.resolvers.go' \\) -delete"
//go:generate bash -c "find ../apis -type d -empty -delete"
//go:generate bash -c "find ../internal/controller -iname 'zz_*' -delete"
//go:generate bash -c "find ../internal/controller -type d -empty -delete"
//go:generate rm -rf ../examples-generated
//go:generate bash -c "find ../cmd/provider -name 'zz_*' -type f -delete"
//go:generate bash -c "find ../cmd/provider -type d -maxdepth 1 -mindepth 1 -empty -delete"

// 2. Scrape Terraform docs -> config/provider-metadata.yaml
//go:generate go run github.com/crossplane/upjet/v2/cmd/scraper -n ${TERRAFORM_PROVIDER_SOURCE} -r ../.work/${TERRAFORM_PROVIDER_SOURCE}/${TERRAFORM_DOCS_PATH} -o ../config/provider-metadata.yaml --prelude-xpath "//text()[contains(., \"page_title\")]"

// 3. Upjet generator: API types, controllers, examples-generated, cmd/provider/zz_*
//go:generate go run ../cmd/generator/main.go ..

// 4. deepcopy methodsets + CRD manifests
//go:generate go run -tags generate sigs.k8s.io/controller-tools/cmd/controller-gen object:headerFile=../hack/boilerplate.go.txt paths=../apis/... crd:allowDangerousTypes=true,crdVersions=v1 output:artifacts:config=../package/crds

// 4b. (optional) enable conversion webhooks on multi-version CRDs
//go:generate go run ../cmd/crdconversion/main.go ../package/crds

// 5. crossplane-runtime methodsets (GetCondition, SetConditions, ...)
//go:generate go run -tags generate github.com/crossplane/crossplane-tools/cmd/angryjet generate-methodsets --header-file=../hack/boilerplate.go.txt ../apis/...

// 6. Rewrite generated resolvers to avoid cross-API-group import cycles
//go:generate go run github.com/crossplane/upjet/v2/cmd/resolver -g <ROOT_GROUP> -a github.com/<ORG>/provider-<name>/internal/apis -s -p ../apis/...

package generate

import (
    _ "sigs.k8s.io/controller-tools/cmd/controller-gen"      //nolint:typecheck
    _ "github.com/crossplane/crossplane-tools/cmd/angryjet"  //nolint:typecheck
    _ "github.com/crossplane/upjet/v2/cmd/scraper"
    _ "github.com/crossplane/upjet/v2/cmd/resolver"
)
```

With namespaced MRs, run step 6 twice — once with `-g <ROOT_GROUP> -p ../apis/cluster/...`
and once with `-g <name>.m.crossplane.io -p ../apis/namespaced/...`.

## `cmd/generator/main.go`

```go
rootDir := os.Args[1]                 // ".." when invoked from generate/
absRootDir, _ := filepath.Abs(rootDir)
provider, err := config.GetProvider(true)               // generationProvider = true
providerNamespaced, err := config.GetProviderNamespaced(true)  // or nil for cluster-only
pipeline.Run(provider, providerNamespaced, absRootDir)
```

## Deletion rules

The cleanup stage deletes regenerable files only. **Do not delete**
`zz_generated.conversion_hubs.go` / `zz_generated.conversion_spokes.go` of *previous*
API versions if you support CRD conversion — those are frozen spokes and must
survive regeneration.

## `config/generated.lst`

`cmd/generatedlist` writes `config.ExternalNameConfigs`' keys, sorted, one per line.
It supports `--check` to fail when the committed file is stale. Hook `generated-lst`
into `generate.done` and `generated-lst-check` into CI. The file is what the
schema-diff automation compares `config/schema.json` against.

## Verifying a generation run

```bash
make generate
git status --porcelain      # expect only intended changes
make lint && make test && make build
```

CI must do the same and fail on any diff — that is the `check-diff` job.
