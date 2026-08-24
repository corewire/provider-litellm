# CI, release and upstream-tracking automation

## `.github/workflows/ci.yml`

Jobs, in dependency order:

| Job | What it does |
|---|---|
| `detect-noop` | `fkirc/skip-duplicate-actions`; optionally computes the e2e scope via `scripts/e2e_dag.py select` |
| `lint` | `golangci/golangci-lint-action` with the pinned `GOLANGCILINT_VERSION` |
| `check-diff` | `make generate` then `git diff --exit-code`; plus `make generated-lst-check`, `make e2e-cases-check`, docs freshness |
| `unit-tests` | `make test` (+ race tests), upload coverage |
| `build` / `build-publish` | QEMU + buildx multi-arch image and xpkg; publish on `main` / `release-*` |
| `e2e-tests` | kind + Crossplane + `make uptest`, matrixed over upstream versions where relevant |
| `schema-version-diff` | `make schema-version-diff` — flags Terraform state-schema version bumps |
| `crddiff` | `make crddiff` — flags breaking CRD changes |

Cache Go build output using `make go.cachedir` as the cache key input.

`check-diff` is the most valuable job in the whole pipeline: it proves the committed
generated code matches `config/`.

## Release workflows

- `auto-release.yaml` — scheduled: if there are relevant changes since the last tag
  and CI is green, bump the semver tag and cut a GitHub Release with generated notes.
- `tag.yml` — `workflow_dispatch` with `version` + `message` inputs for manual tagging.
- `quick-release.yml` (optional) — scheduled multi-arch image/xpkg publish, with an
  optional `crane copy` mirror to a second registry.
- `backport.yml` (optional) — label-driven backports to `release-*` branches.

## Upstream Terraform provider tracking

Two complementary automations, both **dry-run on pull requests** (and path-filtered
to their own sources so they don't run on unrelated PRs) and **live on schedule**:

### `schema-diff-issues.yml` → `scripts/schema_diff_issues.py`

Compares `config/schema.json` (everything upstream offers) against
`config/generated.lst` (what we expose) and files one GitHub issue per
not-yet-exposed resource, skipping resources already tracked by an open issue.
This turns "which resources are still missing?" into a live backlog.

### `provider-release-check.yml` → `scripts/check_provider_release.py`

- `--mode issue`: compare the latest upstream release to `TERRAFORM_PROVIDER_VERSION`
  in the Makefile; file a tracking issue with the full bump checklist.
- `--mode bump`: perform the mechanical bump in the working tree — update the
  Makefile, `go get` the new provider module, `go mod tidy`, `make generate` — and
  emit a PR body summarizing the schema diff (via `version_diff.py`). Committing,
  branching and PR creation stay in the workflow so git identity is controlled there.

### `scripts/version_diff.py`

Given `generated.lst`, an old `schema.json` and a new one, reports new resources,
removed resources, `SchemaVersion` bumps (which imply Terraform state migrations)
and per-attribute additions/removals for generated resources. Exit codes:
`0` no changes, `1` changes detected, `2` error.

## Renovate

`.github/renovate.json` should:

- keep Go modules and GitHub Actions current (grouped, auto-merge for patch/minor),
- treat the **Terraform provider dependency specially** — either exclude it from
  auto-merge or require the `provider-release-check` flow, because bumping it
  regenerates every CRD and may need a state-schema migration,
- pick up `# renovate: datasource=github-releases depName=...` comments in the
  Makefile so `TERRAFORM_PROVIDER_VERSION` is tracked too.

## Repository hygiene

`CODEOWNERS`, a `Dockerfile` based on a digest-pinned `gcr.io/distroless/static`
running as `USER 65532`, and `package/crossplane.yaml` declaring
`capabilities: [safe-start]`.
