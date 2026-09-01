# Testing

## Unit tests

Cover the hand-written code only — generated code is upjet's responsibility:

- `internal/clients` — credential extraction and `TerraformSetupBuilder` (see
  `references/clients.md`)
- `config/` — external-name `GetIDFn`/`GetExternalNameFn` implementations,
  custom extractors, and any lookup logic
- concurrency-sensitive packages under `-race` (`make test.race`)

Exclude `zz_*` from coverage reports (`make cobertura`).

## Examples

- `examples/<group>/<resource>.yaml` — hand-written, realistic, and **used as the e2e
  test input**. Annotate with `upjet.upbound.io/timeout` when a resource is slow.
- `examples-generated/` — produced by upjet; a starting point to copy from, never
  edited in place.

Every exposed managed resource should have at least one example.

## E2E with uptest + chainsaw

```
cluster/test/
├── setup.sh              # creates namespace, credentials Secret and ProviderConfig
├── cases.txt             # one example path per line; '#' comments allowed
├── cases-<variant>.txt   # optional: version- or feature-gated suites
└── chainsaw-config.yaml
```

`setup.sh` must fail fast when required environment variables are missing, create
the credentials `Secret` in `upbound-system`, and apply a `ProviderConfig` named
`default`. Never bake real credentials into the repo — they come from CI secrets.

Wire it up:

```makefile
UPTEST_EXAMPLE_LIST := $(shell grep -v '^\#' cluster/test/cases.txt | paste -sd ',' -)

uptest: $(UPTEST) $(KUBECTL) $(CHAINSAW) $(CROSSPLANE_CLI)
	@KUBECTL=$(KUBECTL) CHAINSAW=$(CHAINSAW) CROSSPLANE_CLI=$(CROSSPLANE_CLI) \
	 CROSSPLANE_NAMESPACE=$(CROSSPLANE_NAMESPACE) \
	 $(UPTEST) e2e "$(UPTEST_EXAMPLE_LIST)" --data-source="${UPTEST_DATASOURCE_PATH}" \
	   --setup-script=cluster/test/setup.sh --default-conditions="Test" --default-timeout=2400s

e2e: local-deploy uptest
```

`local-deploy` builds the provider, brings up kind + Crossplane, installs the local
xpkg, and waits for the `Provider` to be `Installed` and `Healthy`.

## Coverage gates

Add a `e2e-cases-check` target that fails when:

- an example exists that is not referenced by any `cases*.txt`, or
- an exposed managed resource has no example.

Keep a documented exception list (`cluster/test/uncovered-resources.txt`) rather
than silently skipping resources.

## Targeted e2e (large providers)

`scripts/e2e_dag.py` builds `cluster/test/e2e-index.json` mapping each MR kind to
its demos, then, given the changed files of a PR, selects `skip` / `targeted` /
`full` e2e scope. The CI `detect-noop` job consumes this so doc-only PRs do not
spend an hour in kind.

## Conversion tests

If CRDs are multi-version, add chainsaw tests under `cluster/test/conversion/` that
apply an old-version manifest and assert the converted output — this is the only
way to catch broken conversion webhooks before users do.
