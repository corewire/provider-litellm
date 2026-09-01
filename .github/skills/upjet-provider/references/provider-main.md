# `cmd/provider/main.go`

The controller-manager entrypoint. Everything here is hand-written and stable
across regenerations.

## Flags (kingpin, `DefaultEnvars()`)

| Flag | Default | Env |
|---|---|---|
| `--debug` / `-d` | `false` | |
| `--sync` / `-s` | `1h` | manager cache resync |
| `--poll` | `10m` | per-MR drift check |
| `--poll-state-metric` | `5s` | |
| `--leader-election` / `-l` | `false` | `LEADER_ELECTION` |
| `--max-reconcile-rate` | `10` | global reconciles/sec |
| `--max-concurrent-reconciles` | `5` | per controller |
| `--cache-sync-timeout` | `10m` | `CACHE_SYNC_TIMEOUT` |
| `--webhook-port` | `9443` | `WEBHOOK_PORT` |
| `--metrics-bind-address` | `:8080` | `METRICS_BIND_ADDRESS` |
| `--enable-management-policies` | `true` | `ENABLE_MANAGEMENT_POLICIES` |
| `--certs-dir` | `/tls/server` | `CERTS_DIR`, falling back to `TLS_SERVER_CERTS_DIR`, `WEBHOOK_TLS_CERT_DIR` |

Add provider-specific tuning flags (e.g. a client pool size) as needed.

## Manager

```go
mgr, err := ctrl.NewManager(ratelimiter.LimitRESTConfig(cfg, *maxReconcileRate), ctrl.Options{
    LeaderElection:   *leaderElection,
    LeaderElectionID: "crossplane-leader-election-provider-<name>",
    Cache:            cache.Options{SyncPeriod: syncPeriod},
    Controller:       ctrlconfig.Controller{CacheSyncTimeout: *cacheSyncTimeout},
    Metrics:          metricsserver.Options{BindAddress: *metricsBindAddress},
    WebhookServer:    webhook.NewServer(webhook.Options{CertDir: *certsDir, Port: *webhookPort}),
    LeaderElectionResourceLock: resourcelock.LeasesResourceLock,
    LeaseDuration:              ptr(60 * time.Second),
    RenewDeadline:              ptr(50 * time.Second),
})
kingpin.FatalIfError(v1beta1.AddToScheme(mgr.GetScheme()), "...")
kingpin.FatalIfError(apiextensionsv1.AddToScheme(mgr.GetScheme()), "...")
```

Register the MR metrics recorders (`managed.NewMRMetricRecorder()`,
`statemetrics.NewMRStateMetrics()`) with `metrics.Registry`.

## Controller options

```go
feats := &feature.Flags{}
if *enableManagementPolicies { feats.Enable(features.EnableBetaManagementPolicies) }

pc, err := config.GetProvider(false)   // false => runtime (embedded SDK provider)

ws := terraform.NewWorkspaceStore(log,
    terraform.WithDisableInit(true),   // no-fork: never run `terraform init`
    terraform.WithFeatures(feats),
)

o := tjcontroller.Options{
    Options: xpcontroller.Options{
        Logger:                  log,
        MaxConcurrentReconciles: *maxConcurrentReconciles,
        PollInterval:            *pollInterval,
        GlobalRateLimiter:       ratelimiter.NewGlobal(*maxReconcileRate),
        Features:                feats,
        MetricOptions: &xpcontroller.MetricOptions{
            PollStateMetricInterval: *pollStateMetricInterval,
            MRMetrics:               metricRecorder,
            MRStateMetrics:          stateMetrics,
        },
    },
    Provider:              pc,
    WorkspaceStore:        ws,
    OperationTrackerStore: tjcontroller.NewOperationStore(log),
    SetupFn:               clients.TerraformSetupBuilder(),
    PollJitter:            time.Duration(float64(*pollInterval) * 0.05),
}
kingpin.FatalIfError(internalcontroller.Setup(mgr, o), "Cannot setup controllers")
```

`PollJitter` (5% of the poll interval) is important: without it every MR wakes up
in lockstep and hammers the upstream API.

## Safe-start (recommended)

Declare `capabilities: [safe-start]` in `package/crossplane.yaml` and gate
controllers on CRD availability:

```go
if canWatchCRD(mgr) {     // SelfSubjectAccessReview for get/list/watch on CRDs
    g := new(gate.Gate[schema.GroupVersionKind])
    o.Gate = g
    customresourcesgate.Setup(mgr, o)
    internalcontroller.SetupGated(mgr, o)
} else {
    internalcontroller.Setup(mgr, o)   // fallback for restricted RBAC
}
```

## Resilience and webhooks (larger providers)

- Wrap the manager so one failing controller cannot take down the process or the
  conversion webhook (provider-keycloak's `internal/resilience.WrapManager`).
- When you have multi-version CRDs, call `SetupWebhookWithManager` and
  `conversion.RegisterConversions(...)` whenever `certsDir` is set, and patch the
  CRDs with `cmd/crdconversion` during generation.

## Dual scope

If namespaced MRs are generated, build a second `tjcontroller.Options` from
`config.GetProviderNamespaced(false)` and set up both controller trees.
