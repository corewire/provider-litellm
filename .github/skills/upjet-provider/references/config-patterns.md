# `config/` patterns

## `config/provider.go`

```go
const (
    resourcePrefix      = "<name>"                    // TF resource prefix, e.g. "keycloak"
    modulePath          = "github.com/<ORG>/provider-<name>"
    rootGroup           = "<name>.crossplane.io"
    rootGroupNamespaced = "<name>.m.crossplane.io"    // only if namespaced MRs are generated
)

//go:embed schema.json
var providerSchema string

//go:embed provider-metadata.yaml
var providerMetadata string
```

`getProviderSchema` rebuilds a `*schema.Provider` from the embedded JSON so that
**generation** never touches a live provider binary (and so numeric types are not
mangled into `int`):

```go
func getProviderSchema(s string) (*schema.Provider, error) {
    ps := tfjson.ProviderSchemas{}
    if err := ps.UnmarshalJSON([]byte(s)); err != nil { panic(err) }
    if len(ps.Schemas) != 1 {
        return nil, errors.Errorf("there should exactly be 1 provider schema but there are %d", len(ps.Schemas))
    }
    var rs map[string]*tfjson.Schema
    for _, v := range ps.Schemas { rs = v.ResourceSchemas; break }
    return &schema.Provider{ResourcesMap: conversiontfjson.GetV2ResourceMap(rs)}, nil
}
```

`GetProvider(generationProvider bool)`:

```go
var p *schema.Provider
if generationProvider {
    p, err = getProviderSchema(providerSchema)   // code generation
} else {
    p = <name>Provider.Provider()                // runtime: the real, embedded SDK provider
}

pc := ujconfig.NewProvider([]byte(providerSchema), resourcePrefix, modulePath, []byte(providerMetadata),
    ujconfig.WithIncludeList([]string{}),
    ujconfig.WithTerraformPluginSDKIncludeList(ExternalNameConfigured()),
    ujconfig.WithTerraformPluginFrameworkIncludeList([]string{}),
    ujconfig.WithTerraformProvider(p),
    ujconfig.WithFeaturesPackage("internal/features"),
    ujconfig.WithDefaultResourceOptions(
        ExternalNameConfigurations(),
        KnownReferencers(),
    ),
    ujconfig.WithRootGroup(rootGroup),
)

for _, configure := range []func(*ujconfig.Provider){
    realm.Configure, group.Configure, /* ... one per config/<group> package ... */
} {
    configure(pc)
}
pc.ConfigureResources()
```

Include-list rules:

- SDKv2 resources → `WithTerraformPluginSDKIncludeList`
- plugin-framework resources → `WithTerraformPluginFrameworkIncludeList`
- `WithIncludeList` is the legacy (terraform-CLI) list; keep it empty for no-fork.
- All lists take regexes; `ExternalNameConfigured()` should emit `"<resource>$"` entries.

## `config/external_name.go`

```go
var ExternalNameConfigs = map[string]ujconfig.ExternalName{
    "<name>_thing": ujconfig.IdentifierFromProvider,
    ...
}

func ExternalNameConfigured() []string   // -> []string{"<name>_thing$", ...}
func ExternalNameConfigurations() ujconfig.ResourceOption // sets r.ExternalName from the map
```

Choosing an external-name strategy:

| Situation | Use |
|---|---|
| API assigns an opaque ID on create | `ujconfig.IdentifierFromProvider` |
| The TF ID is a user-specified field | `ujconfig.NameAsIdentifier` (and set `r.ExternalName.OmittedFields`) |
| TF ID is a template of several fields | `ujconfig.TemplatedStringAsIdentifier("name", "{{ .parameters.realm_id }}/{{ .external_name }}")` |
| Resource must be discoverable by human-readable fields | custom `GetIDFn`/`GetExternalNameFn` (provider-keycloak's `config/lookup` queries the API to resolve a name → UUID) |

Every entry in this map becomes a CRD. Adding an entry and running `make generate`
is the entire "expose a new resource" workflow.

## Per-group configuration — `config/<group>/config.go`

```go
func Configure(p *ujconfig.Provider) {
    p.AddResourceConfigurator("<name>_thing", func(r *ujconfig.Resource) {
        r.ShortGroup = "thing"          // API group: thing.<ROOT_GROUP>
        r.Kind = "Thing"                // override the derived Kind if needed
        r.References["parent_id"] = ujconfig.Reference{
            TerraformName: "<name>_parent",
            Extractor:     `github.com/crossplane/upjet/v2/pkg/resource.ExtractResourceID()`,
        }
        r.TerraformResource.Schema["secret_field"].Sensitive = true
        r.LateInitializer.IgnoredFields = []string{"noisy_field"}
        r.UseAsync = true
    })
}
```

Knobs worth knowing:

| Knob | Purpose |
|---|---|
| `r.ShortGroup` | Groups resources into API groups; keep groups small and topical |
| `r.Kind` | Fix awkward auto-derived kinds (`DefaultGroups`, `RealmEvents`) |
| `r.References[field]` | Cross-resource refs; generates `<field>Ref`/`<field>Selector` |
| `Reference.Extractor` | `ExtractResourceID()`, `ExtractParamPath("name", false)`, or a custom extractor |
| `r.TerraformResource.Schema[f].Sensitive` | Routes the field through a `SecretKeySelector` / connection details |
| `r.TerraformResource.Schema[f].ValidateFunc` | Inject validation the upstream provider lacks |
| `r.LateInitializer.IgnoredFields` | Stop late-init fights on server-defaulted fields |
| `r.MetaResource.ArgumentDocs` | Fix bad scraped docs |
| `r.UseAsync` | Long-running create/update |
| `r.OverrideFieldNames` | Resolve Go type-name collisions |

### `KnownReferencers()`

A `ResourceOption` applied to *every* resource that wires up the handful of
foreign-key field names that recur across the whole provider (in keycloak:
`realm_id`, `organization_id`, `client_scope_id`, `role_id(s)`). Skip fields that
are `Computed && !Optional` or `Sensitive`. This is far more maintainable than
repeating the same reference in a hundred per-resource configurators.

## Group and kind design rules

- One `config/<group>/config.go` per API group; the package name is the group.
- Keep `ShortGroup` stable — it is part of the CRD's `apiVersion`.
- Prefer references over free-form ID strings: they are what makes a Crossplane
  provider composable.
- Mark anything credential-like as `Sensitive` before the first release; changing it
  later is a breaking CRD change.
