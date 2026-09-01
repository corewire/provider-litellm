# ====================================================================================
# provider-litellm – Tilt local development environment
#
# Prerequisites:
#   - kind          (cluster creation)
#   - kubectl
#   - helm
#   - tilt >= 0.33
#
# Quick start:
#   make tilt-up          # creates the kind cluster and starts Tilt
#   make tilt-down        # tears everything down
#
# Or manually:
#   kind create cluster --name provider-litellm
#   tilt up
# ====================================================================================

load("ext://helm_resource", "helm_resource", "helm_repo")
load("ext://namespace", "namespace_create")

# ---------------------------------------------------------------------------
# Read local settings (optional overrides). Copy tilt-settings.yaml.example
# to tilt-settings.yaml and adjust as needed.
# ---------------------------------------------------------------------------
settings = read_yaml("tilt-settings.yaml", default={})

IMAGE_REPO    = settings.get("image_repo",    "ghcr.io/corewire/provider-litellm")
PROVIDER_TAG  = settings.get("provider_tag",  "dev")
PROVIDER_IMG  = "{}:{}".format(IMAGE_REPO, PROVIDER_TAG)

LITELLM_MASTER_KEY = settings.get("litellm_master_key", "sk-local-dev-key")
LITELLM_API_BASE   = "http://litellm.litellm.svc.cluster.local:4000"

# ---------------------------------------------------------------------------
# 1. Provider binary – rebuild on any Go source change
# ---------------------------------------------------------------------------
local_resource(
    "go-build",
    cmd = "CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o _output/bin/provider ./cmd/provider/...",
    deps = ["./cmd", "./internal", "./apis", "./config"],
    labels = ["provider"],
)

# ---------------------------------------------------------------------------
# 2. Provider container image – rebuild whenever the binary changes
# ---------------------------------------------------------------------------
docker_build(
    PROVIDER_IMG,
    context = ".",
    dockerfile = "cluster/images/provider-litellm/Dockerfile",
    only = [
        "_output/bin/provider",
        "cluster/images/provider-litellm/Dockerfile",
    ],
    # Tilt will automatically set TARGETOS/TARGETARCH for local arch
    build_args = {"TARGETOS": "linux", "TARGETARCH": "amd64"},
    # Live-update: copy only the binary so restarts are fast
    live_update = [
        sync("_output/bin/provider", "/usr/local/bin/provider"),
        run("/usr/local/bin/provider --version", trigger=["_output/bin/provider"]),
    ],
)

# ---------------------------------------------------------------------------
# 3. Crossplane – install via Helm
# ---------------------------------------------------------------------------
helm_repo(
    "crossplane-stable",
    "https://charts.crossplane.io/stable",
    labels = ["crossplane"],
)

namespace_create("crossplane-system")

helm_resource(
    "crossplane",
    "crossplane-stable/crossplane",
    namespace = "crossplane-system",
    flags = [
        "--version", "2.4.0",
        "--wait",
    ],
    labels = ["crossplane"],
    resource_deps = ["crossplane-stable"],
)

# ---------------------------------------------------------------------------
# 4. LiteLLM – deploy the in-cluster instance
# ---------------------------------------------------------------------------
k8s_yaml("cluster/test/litellm/deploy.yaml")

k8s_resource(
    "litellm",
    namespace = "litellm",
    port_forwards = "4000:4000",  # makes LiteLLM reachable at http://localhost:4000
    labels = ["litellm"],
    resource_deps = [],
)

# ---------------------------------------------------------------------------
# 5. upbound-system namespace + credentials Secret + ProviderConfig
# ---------------------------------------------------------------------------
namespace_create("upbound-system")

k8s_yaml(blob("""
apiVersion: v1
kind: Secret
metadata:
  name: litellm-credentials
  namespace: upbound-system
type: Opaque
stringData:
  credentials: |
    LITELLM_API_BASE={api_base}
    LITELLM_API_KEY={api_key}
""".format(api_base = LITELLM_API_BASE, api_key = LITELLM_MASTER_KEY)))

k8s_yaml(blob("""
apiVersion: litellm.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: upbound-system
      name: litellm-credentials
      key: credentials
"""))

# The ProviderConfig CRD is installed by the provider package; declare the
# dependency so Tilt orders the apply correctly.
k8s_resource(
    new_name = "provider-config-default",
    objects = ["default:ProviderConfig"],
    labels = ["provider"],
    resource_deps = ["provider-litellm-pkg"],
)

# ---------------------------------------------------------------------------
# 6. Provider package – build .xpkg and install via Package CR
# ---------------------------------------------------------------------------

# Build the Crossplane package and load it into the kind cluster image cache.
local_resource(
    "xpkg-build",
    cmd = (
        "docker build -t {img} -f cluster/images/provider-litellm/Dockerfile "
        "--build-arg TARGETOS=linux --build-arg TARGETARCH=amd64 . && "
        "kind load docker-image {img} --name provider-litellm"
    ).format(img = PROVIDER_IMG),
    deps = ["_output/bin/provider"],
    labels = ["provider"],
    resource_deps = ["go-build"],
)

# Deploy the Provider package CR pointing at our local image.
k8s_yaml(blob("""
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-litellm
spec:
  package: {img}
  packagePullPolicy: Never
""".format(img = PROVIDER_IMG)))

k8s_resource(
    "provider-litellm-pkg",
    new_name = "provider-litellm-pkg",
    labels = ["provider"],
    resource_deps = ["crossplane", "xpkg-build"],
)

# ---------------------------------------------------------------------------
# 7. Convenience: watch logs from the provider pod
# ---------------------------------------------------------------------------
local_resource(
    "provider-logs",
    serve_cmd = (
        "kubectl logs -n crossplane-system "
        "-l pkg.crossplane.io/revision=provider-litellm-1 "
        "--all-containers --follow --ignore-errors 2>&1 || true"
    ),
    labels = ["provider"],
    resource_deps = ["provider-litellm-pkg"],
)
