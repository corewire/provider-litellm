# ====================================================================================
# Setup Project

PROJECT_NAME     ?= provider-litellm
PROJECT_REPO     ?= github.com/corewire/$(PROJECT_NAME)

export TERRAFORM_VERSION ?= 1.5.7

# Do not allow a version of terraform greater than 1.5.x, due to versions 1.6+
# being licensed under BSL, which is not permitted for open-source.
TERRAFORM_VERSION_VALID := $(shell [ "$(TERRAFORM_VERSION)" = "`printf "$(TERRAFORM_VERSION)\n1.6" | sort -V | head -n1`" ] && echo 1 || echo 0)

export TERRAFORM_PROVIDER_SOURCE  ?= BerriAI/litellm
export TERRAFORM_PROVIDER_REPO    ?= https://github.com/BerriAI/terraform-provider-litellm
# renovate: datasource=github-releases depName=BerriAI/terraform-provider-litellm
export TERRAFORM_PROVIDER_VERSION ?= 0.4.0
export TERRAFORM_PROVIDER_DOWNLOAD_NAME ?= terraform-provider-litellm
export TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX ?= ${TERRAFORM_PROVIDER_REPO}/releases/download/v$(TERRAFORM_PROVIDER_VERSION)
export TERRAFORM_NATIVE_PROVIDER_BINARY ?= terraform-provider-litellm_v$(TERRAFORM_PROVIDER_VERSION)
export TERRAFORM_DOCS_PATH        ?= docs/resources
export TERRAFORM_FILE_MIRROR      ?= .terraform.d/plugins
export TERRAFORM_FILE_MIRROR_REPO ?= ${TERRAFORM_FILE_MIRROR}/registry.terraform.io

export GOLANGCILINT_VERSION ?= 2.12.2

PLATFORMS ?= linux_amd64 linux_arm64

-include build/makelib/common.mk

# ====================================================================================
# Setup Output

-include build/makelib/output.mk

# ====================================================================================
# Setup Go

NPROCS ?= 1
GO_TEST_PARALLEL := $(shell echo $$(( $(NPROCS) / 2 )))

GO_REQUIRED_VERSION ?= 1.24
GO_STATIC_PACKAGES  = $(GO_PROJECT)/cmd/provider $(GO_PROJECT)/cmd/generator
GO_LDFLAGS          += -X $(GO_PROJECT)/internal/version.Version=$(VERSION)
GO_SUBDIRS          += cmd internal apis config
-include build/makelib/golang.mk

# ====================================================================================
# Setup Kubernetes tools

KUBECTL_VERSION  ?= v1.32.2
KIND_VERSION      = v0.32.0
UP_VERSION        = v0.38.4
UP_CHANNEL        = stable
UPTEST_VERSION    = v2.2.0
-include build/makelib/k8s_tools.mk

# ====================================================================================
# Setup Images

REGISTRY_ORGS ?= xpkg.upbound.io/corewire
IMAGES = $(PROJECT_NAME)
-include build/makelib/imagelight.mk

# ====================================================================================
# Setup XPKG

XPKG_REG_ORGS          ?= xpkg.upbound.io/corewire
XPKG_REG_ORGS_NO_PROMOTE ?= xpkg.upbound.io/corewire
XPKGS = $(PROJECT_NAME)
-include build/makelib/xpkg.mk

# ====================================================================================
# Fallthrough

# run `make help` to see the targets and options

# We want submodules to be set up the first time `make` is run.
# We manage the build/ folder and its Makefiles as a submodule.
fallthrough: submodules
	@echo Initial setup complete. Running make again . . .
	@make

xpkg.build.provider-litellm: do.build.images

build.init: $(UP) check-terraform-version $(CROSSPLANE_CLI)

# ====================================================================================
# Setup Terraform for fetching provider schema

TERRAFORM             := $(TOOLS_HOST_DIR)/terraform-$(TERRAFORM_VERSION)
TERRAFORM_WORKDIR     := $(WORK_DIR)/terraform
TERRAFORM_PROVIDER_SCHEMA := config/schema.json

check-terraform-version:
ifneq ($(TERRAFORM_VERSION_VALID),1)
	$(error invalid TERRAFORM_VERSION $(TERRAFORM_VERSION), must be less than 1.6.0 since that version introduced a not-permitted BSL license)
endif

$(TERRAFORM): check-terraform-version
	@$(INFO) installing terraform $(HOSTOS)-$(HOSTARCH)
	@mkdir -p $(TOOLS_HOST_DIR)/tmp-terraform
	@curl -fsSL https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_$(SAFEHOST_PLATFORM).zip -o $(TOOLS_HOST_DIR)/tmp-terraform/terraform.zip
	@unzip $(TOOLS_HOST_DIR)/tmp-terraform/terraform.zip -d $(TOOLS_HOST_DIR)/tmp-terraform
	@mv $(TOOLS_HOST_DIR)/tmp-terraform/terraform $(TERRAFORM)
	@rm -fr $(TOOLS_HOST_DIR)/tmp-terraform
	@$(OK) installing terraform $(HOSTOS)-$(HOSTARCH)

$(TERRAFORM_PROVIDER_SCHEMA): $(TERRAFORM)
	@$(INFO) generating provider schema for $(TERRAFORM_PROVIDER_SOURCE) $(TERRAFORM_PROVIDER_VERSION)
	@mkdir -p $(TERRAFORM_WORKDIR)
	@$(MAKE) download-tf-provider-platforms
	@echo '{"terraform":[{"required_providers":[{"provider":{"source":"'"$(TERRAFORM_PROVIDER_SOURCE)"'","version":"'"$(TERRAFORM_PROVIDER_VERSION)"'"}}],"required_version":"'"$(TERRAFORM_VERSION)"'"}]}' > $(TERRAFORM_WORKDIR)/main.tf.json
	@echo 'provider_installation { filesystem_mirror { path = "$(TERRAFORM_WORKDIR)/$(TERRAFORM_FILE_MIRROR)" include = ["*/*/*"] } }' > $(TERRAFORM_WORKDIR)/config.tfrc
	@TF_CLI_CONFIG_FILE=$(TERRAFORM_WORKDIR)/config.tfrc $(TERRAFORM) -chdir=$(TERRAFORM_WORKDIR) init -no-color > $(TERRAFORM_WORKDIR)/terraform-logs.txt 2>&1
	@TF_CLI_CONFIG_FILE=$(TERRAFORM_WORKDIR)/config.tfrc $(TERRAFORM) -chdir=$(TERRAFORM_WORKDIR) providers schema -json=true > $(TERRAFORM_PROVIDER_SCHEMA) 2>> $(TERRAFORM_WORKDIR)/terraform-logs.txt
	@$(OK) generating provider schema for $(TERRAFORM_PROVIDER_SOURCE) $(TERRAFORM_PROVIDER_VERSION)

download-tf-provider-platforms: $(foreach p,$(PLATFORMS), download-tf-provider-platform.$(p))

download-tf-provider-platform.%:
	@$(MAKE) download-tf-provider-platform PLATFORM=$*

download-tf-provider-platform:
	@$(INFO) downloading provider for platform $(PLATFORM)
	@mkdir -p $(TERRAFORM_WORKDIR)/$(TERRAFORM_FILE_MIRROR_REPO)/$(TERRAFORM_PROVIDER_SOURCE)/$(TERRAFORM_PROVIDER_VERSION)/${PLATFORM}
	@curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
		${TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX}/${TERRAFORM_PROVIDER_DOWNLOAD_NAME}_${TERRAFORM_PROVIDER_VERSION}_${PLATFORM}.zip \
		-o $(TERRAFORM_WORKDIR)/$(TERRAFORM_FILE_MIRROR_REPO)/$(TERRAFORM_PROVIDER_SOURCE)/$(TERRAFORM_PROVIDER_VERSION)/${PLATFORM}/terraform.zip
	@unzip -o -qq \
		$(TERRAFORM_WORKDIR)/$(TERRAFORM_FILE_MIRROR_REPO)/$(TERRAFORM_PROVIDER_SOURCE)/$(TERRAFORM_PROVIDER_VERSION)/${PLATFORM}/terraform.zip \
		-d $(TERRAFORM_WORKDIR)/$(TERRAFORM_FILE_MIRROR_REPO)/$(TERRAFORM_PROVIDER_SOURCE)/$(TERRAFORM_PROVIDER_VERSION)/${PLATFORM}/
	@rm $(TERRAFORM_WORKDIR)/$(TERRAFORM_FILE_MIRROR_REPO)/$(TERRAFORM_PROVIDER_SOURCE)/$(TERRAFORM_PROVIDER_VERSION)/${PLATFORM}/terraform.zip

pull-docs:
	@if [ ! -d "$(WORK_DIR)/$(TERRAFORM_PROVIDER_SOURCE)" ]; then \
		mkdir -p "$(WORK_DIR)/$(TERRAFORM_PROVIDER_SOURCE)" && \
		git clone -c advice.detachedHead=false --depth 1 --filter=blob:none \
			--branch "v$(TERRAFORM_PROVIDER_VERSION)" --sparse \
			"$(TERRAFORM_PROVIDER_REPO)" "$(WORK_DIR)/$(TERRAFORM_PROVIDER_SOURCE)"; \
	fi
	@git -C "$(WORK_DIR)/$(TERRAFORM_PROVIDER_SOURCE)" sparse-checkout set "$(TERRAFORM_DOCS_PATH)"

generate.init: $(TERRAFORM_PROVIDER_SCHEMA) pull-docs

.PHONY: $(TERRAFORM_PROVIDER_SCHEMA) pull-docs check-terraform-version

# ====================================================================================
# Targets

go.cachedir:
	@go env GOCACHE

cobertura:
	@cat $(GO_TEST_OUTPUT)/coverage.txt | \
		grep -v zz_ | \
		$(GOCOVER_COBERTURA) > $(GO_TEST_OUTPUT)/cobertura-coverage.xml

submodules:
	@git submodule sync
	@git submodule update --init --recursive

run: go.build
	@$(INFO) Running Crossplane locally out-of-cluster . . .
	@UPBOUND_CONTEXT="local" $(GO_OUT_DIR)/provider --debug

# ====================================================================================
# End to End Testing

CHAINSAW_VERSION = 0.2.15
CHAINSAW         := $(TOOLS_HOST_DIR)/chainsaw-$(CHAINSAW_VERSION)
CROSSPLANE_VERSION     = 2.0.2
CROSSPLANE_CLI_VERSION = v2.0.2
CROSSPLANE_NAMESPACE   = crossplane-system
CROSSPLANE_CHART_DIR   := $(TOOLS_HOST_DIR)/crossplane-chart-$(CROSSPLANE_VERSION)
CROSSPLANE_CHART       := $(CROSSPLANE_CHART_DIR)/Chart.yaml
-include build/makelib/local.xpkg.mk
-include build/makelib/controlplane.mk

$(CROSSPLANE_CLI):
	@$(INFO) installing Crossplane CLI $(CROSSPLANE_CLI_VERSION)
	@rm -rf $(TOOLS_HOST_DIR)/tmp-crossplane-cli
	@mkdir -p $(dir $(CROSSPLANE_CLI)) $(TOOLS_HOST_DIR)/tmp-crossplane-cli
	@GOBIN=$(TOOLS_HOST_DIR)/tmp-crossplane-cli go install github.com/crossplane/crossplane/v2/cmd/crank@$(CROSSPLANE_CLI_VERSION)
	@mv $(TOOLS_HOST_DIR)/tmp-crossplane-cli/crank $(CROSSPLANE_CLI)
	@rm -rf $(TOOLS_HOST_DIR)/tmp-crossplane-cli
	@$(OK) installing Crossplane CLI $(CROSSPLANE_CLI_VERSION)

$(CROSSPLANE_CHART):
	@$(INFO) downloading Crossplane chart $(CROSSPLANE_VERSION)
	@rm -rf $(CROSSPLANE_CHART_DIR) $(TOOLS_HOST_DIR)/tmp-crossplane-chart
	@mkdir -p $(CROSSPLANE_CHART_DIR) $(TOOLS_HOST_DIR)/tmp-crossplane-chart
	@curl -fsSL https://github.com/crossplane/crossplane/archive/refs/tags/v$(CROSSPLANE_VERSION).tar.gz | tar -xz -C $(TOOLS_HOST_DIR)/tmp-crossplane-chart
	@cp -R $(TOOLS_HOST_DIR)/tmp-crossplane-chart/*/cluster/charts/crossplane/. $(CROSSPLANE_CHART_DIR)/
	@rm -rf $(TOOLS_HOST_DIR)/tmp-crossplane-chart
	@$(OK) downloading Crossplane chart $(CROSSPLANE_VERSION)

$(CHAINSAW):
	@$(INFO) installing chainsaw $(CHAINSAW_VERSION)
	@rm -f $(CHAINSAW).tar.gz
	@curl --retry 5 --retry-delay 2 --retry-all-errors -fsSLo $(CHAINSAW).tar.gz --create-dirs \
		https://github.com/kyverno/chainsaw/releases/download/v$(CHAINSAW_VERSION)/chainsaw_$(SAFEHOST_PLATFORM).tar.gz || $(FAIL)
	@tar -xvf $(CHAINSAW).tar.gz chainsaw
	@mv chainsaw $(CHAINSAW)
	@chmod +x $(CHAINSAW)
	@rm $(CHAINSAW).tar.gz
	@$(OK) installing chainsaw $(CHAINSAW_VERSION)

controlplane.up: $(HELM) $(KUBECTL) $(KIND) $(CROSSPLANE_CHART)
	@$(INFO) setting up controlplane
	@$(KIND) get kubeconfig --name $(KIND_CLUSTER_NAME) >/dev/null 2>&1 || $(KIND) create cluster --name=$(KIND_CLUSTER_NAME)
	@$(KUBECTL) config use-context "kind-$(KIND_CLUSTER_NAME)"
	@if ! $(HELM) get notes -n $(CROSSPLANE_NAMESPACE) crossplane >/dev/null 2>&1; then \
		$(HELM) install crossplane --create-namespace --namespace=$(CROSSPLANE_NAMESPACE) \
			--set image.tag=v$(CROSSPLANE_VERSION) $(CROSSPLANE_CHART_DIR); \
	fi

UPTEST_EXAMPLE_LIST := $(shell grep -v '^\#' cluster/test/cases.txt | paste -sd ',' -)

uptest: $(UPTEST) $(KUBECTL) $(CHAINSAW) $(CROSSPLANE_CLI)
	@$(INFO) running automated tests
	@KUBECTL=$(KUBECTL) CHAINSAW=$(CHAINSAW) CROSSPLANE_CLI=$(CROSSPLANE_CLI) CROSSPLANE_NAMESPACE=$(CROSSPLANE_NAMESPACE) \
		$(UPTEST) e2e "$(UPTEST_EXAMPLE_LIST)" --data-source="${UPTEST_DATASOURCE_PATH}" \
		--setup-script=cluster/test/setup.sh --default-conditions="Test" --default-timeout=2400s || $(FAIL)
	@$(OK) running automated tests

local-deploy: build controlplane.up local.xpkg.deploy.provider.$(PROJECT_NAME)
	@$(INFO) running locally built provider
	@$(KUBECTL) wait crd providers.pkg.crossplane.io --for=create --timeout 5m
	@$(KUBECTL) wait provider.pkg $(PROJECT_NAME) --for condition=Healthy --for condition=Installed --for=create --timeout 5m
	@$(OK) running locally built provider

e2e: local-deploy uptest

.PHONY: uptest local-deploy e2e submodules cobertura go.cachedir run
