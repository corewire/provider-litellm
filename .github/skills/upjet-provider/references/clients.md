# `internal/clients/<name>.go`

This package converts a `ProviderConfig` into a `terraform.Setup` for every
reconcile. In the no-fork model the returned `Setup.Configuration` map is fed
straight into the embedded provider's `Configure`, so its keys must match the
Terraform provider's **provider block schema** exactly (`api_base`, `api_key`,
`url`, `client_id`, ...).

## Skeleton

```go
func TerraformSetupBuilder() terraform.SetupFn {
    return func(ctx context.Context, kube client.Client, mg resource.Managed) (terraform.Setup, error) {
        ps := terraform.Setup{}

        // crossplane-runtime v2: GetProviderConfigReference() is on ModernManaged
        // (namespaced/modern MRs) and LegacyManaged (cluster-scoped legacy MRs),
        // not on resource.Managed.
        mmg, ok := mg.(resource.ModernManaged)
        if !ok { return ps, errors.New(errNoProviderConfig) }
        ref := mmg.GetProviderConfigReference()
        if ref == nil { return ps, errors.New(errNoProviderConfig) }

        pc := &v1beta1.ProviderConfig{}
        if err := kube.Get(ctx, types.NamespacedName{Name: ref.Name}, pc); err != nil {
            return ps, errors.Wrap(err, errGetProviderConfig)
        }

        creds, err := ExtractCredentials(ctx, pc.Spec.Credentials.Source, kube,
            pc.Spec.Credentials.CommonCredentialSelectors)
        if err != nil { return ps, errors.Wrap(err, errExtractCredentials) }

        ps.Configuration = map[string]any{}
        for k, v := range creds { ps.Configuration[k] = v }

        // Fail fast and loudly on missing required provider attributes.
        for _, k := range []string{"api_base", "api_key"} {
            if _, ok := ps.Configuration[k]; !ok {
                return ps, errors.Errorf("required configuration key %q is missing", k)
            }
        }
        return ps, nil
    }
}
```

If the provider supports both cluster-scoped and namespaced MRs, dispatch on the
interface: `resource.LegacyManaged` → cluster `ProviderConfig`,
`resource.ModernManaged` → namespaced `ProviderConfig` / `ClusterProviderConfig`.

## Credential extraction

Support both shapes, because both are in the wild:

1. The secret key referenced by `secretRef.key` holds a **JSON document** of the
   provider configuration (the upjet default; fall back to
   `resource.CommonCredentialExtractor` if the value is not JSON).
2. The secret has **one key per provider attribute** (`url`, `client_id`, ...),
   which is far friendlier for users and for `ExternalSecret`-managed secrets.

Normalize what you can: trim trailing slashes from URLs, coerce `"true"`/`"false"`
strings to bool for boolean provider attributes, and reject empty required values.

## Never log credentials

Error messages must name the *key* that is missing or malformed, never the value.
Do not put `ps.Configuration` into a log line or an error.

## Client reuse and concurrency (scale-up considerations)

Naively calling the provider's `Configure` on every reconcile re-authenticates on
every reconcile. For any provider whose auth is expensive or session-quota bound:

- **Cache the configured meta** in a `sync.Map` keyed by a SHA-256 of the
  configuration map; guard the cache-miss path with a mutex so a burst of
  reconciles produces one login, not N.
- **Pool sibling clients** (provider-keycloak's `internal/tfconcurrency`) and wrap
  the SDK provider (`tfconcurrency.WrapProvider(p)`) so concurrent reconciles do
  not share one non-thread-safe HTTP client.
- **Log out on shutdown**: register a `manager.Runnable` that waits on `ctx.Done()`
  and terminates cached sessions with a bounded timeout (~30s).

Only add this machinery when the upstream client actually needs it — start simple,
measure, then optimize.

## Tests

`internal/clients/<name>_test.go` should cover, with a fake client:

- missing `providerConfigRef` → error
- missing secret / missing key → wrapped error
- JSON-document secret → parsed configuration
- per-key secret → parsed configuration
- missing required attribute → explicit error

Run concurrency-sensitive packages with `-race` (`make test.race`).
