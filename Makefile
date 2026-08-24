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
export TERRAFORM_PROVIDER_VERSION ?= 1.98.0
export TERRAFORM_PROVIDER_DOWNLOAD_NAME ?= terraform-provider-litellm
export TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX ?= ${TERRAFORM_PROVIDER_REPO}/releases/download/v$(TERRAFORM_PROVIDER_VERSION)
export TERRAFORM_NATIVE_PROVIDER_BINARY ?= terraform-provider-litellm_v$(TERRAFORM_PROVIDER_VERSION)
export TERRAFORM_DOCS_PATH        ?= docs/resources
export TERRAFORM_FILE_MIRROR      ?= .terraform.d/plugins
export TERRAFORM_FILE_MIRROR_REPO ?= ${TERRAFORM_FILE_MIRROR}/registry.terraform.io

export GOLANGCILINT_VERSION ?= 2.13.1

PLATFORMS ?= linux_amd64 linux_arm64

-include build/makelib/common.mk

# ====================================================================================
# Setup Output

-include build/makelib/output.mk

# ====================================================================================
# Setup Go

NPROCS ?= 1
GO_TEST_PARALLEL := $(shell echo $$(( $(NPROCS) / 2 )))

GO_REQUIRED_VERSION ?= 1.27.0
GO_STATIC_PACKAGES  = $(GO_PROJECT)/cmd/provider $(GO_PROJECT)/cmd/generator
GO_LDFLAGS          += -X $(GO_PROJECT)/internal/version.Version=$(VERSION)
GO_SUBDIRS          += cmd internal apis config generate
-include build/makelib/golang.mk

# ====================================================================================
# Setup Kubernetes tools

KUBECTL_VERSION        ?= v1.36.4
KIND_VERSION            = v0.32.0
UPTEST_VERSION          = v2.2.0
CROSSPLANE_CLI_VERSION  = v2.4.0
CROSSPLANE_VERSION      = 2.4.0
CROSSPLANE_NAMESPACE    = crossplane-system
KIND_CLUSTER_NAME      ?= $(PROJECT_NAME)
-include build/makelib/k8s_tools.mk

# ====================================================================================
# Setup Images

REGISTRY_ORGS ?= ghcr.io/corewire
IMAGES = $(PROJECT_NAME)
-include build/makelib/imagelight.mk

# ====================================================================================
# Setup XPKG

XPKG_REG_ORGS          ?= ghcr.io/corewire
XPKG_REG_ORGS_NO_PROMOTE ?= ghcr.io/corewire
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

build.init: check-terraform-version $(CROSSPLANE_CLI)

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

# The upjet code generator shells out to goimports, so it has to be on PATH
# before `go generate` runs.
GOIMPORTS := $(TOOLS_HOST_DIR)/goimports
export PATH := $(TOOLS_HOST_DIR):$(PATH)

$(GOIMPORTS):
	@$(INFO) installing goimports
	@mkdir -p $(TOOLS_HOST_DIR)
	@GOBIN=$(TOOLS_HOST_DIR) go install golang.org/x/tools/cmd/goimports || $(FAIL)
	@$(OK) installing goimports

generate.init: $(TERRAFORM_PROVIDER_SCHEMA) pull-docs $(GOIMPORTS)

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

# Write config/generated.lst from config.ExternalNameConfigs so it can be
# committed and used by the schema-diff-issues automation.
generated-lst:
	@go run ./cmd/generatedlist config/generated.lst

# Verify that config/generated.lst matches config.ExternalNameConfigs. Exits
# non-zero when the file is stale. Run generated-lst to fix.
generated-lst-check:
	@go run ./cmd/generatedlist --check config/generated.lst

generate.done: generated-lst

.PHONY: generated-lst generated-lst-check

# ====================================================================================
# End to End Testing

CHAINSAW_VERSION = 0.2.15
CHAINSAW         := $(TOOLS_HOST_DIR)/chainsaw-$(CHAINSAW_VERSION)
-include build/makelib/local.xpkg.mk
-include build/makelib/controlplane.mk

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

UPTEST_EXAMPLE_LIST := $(shell grep -v '^\#' cluster/test/cases.txt | paste -sd ',' -)

uptest: $(UPTEST) $(KUBECTL) $(CHAINSAW) $(CROSSPLANE_CLI)
	@$(INFO) running automated tests
	@KUBECTL=$(KUBECTL) CHAINSAW=$(CHAINSAW) CROSSPLANE_CLI=$(CROSSPLANE_CLI) CROSSPLANE_NAMESPACE=$(CROSSPLANE_NAMESPACE) \
		$(UPTEST) e2e "$(UPTEST_EXAMPLE_LIST)" --data-source="${UPTEST_DATASOURCE_PATH}" \
		--setup-script=cluster/test/setup.sh --default-conditions="Test" --default-timeout=2400s || $(FAIL)
	@$(OK) running automated tests

chainsaw: $(CHAINSAW) $(KUBECTL)
	@$(INFO) running chainsaw e2e tests
	@cluster/test/setup.sh
	@$(CHAINSAW) test --config cluster/test/chainsaw-config.yaml cluster/test/chainsaw/ || $(FAIL)
	@$(OK) running chainsaw e2e tests

local-deploy: build controlplane.up local.xpkg.deploy.provider.$(PROJECT_NAME)
	@$(INFO) running locally built provider
	@$(KUBECTL) wait crd providers.pkg.crossplane.io --for=create --timeout 5m
	@$(KUBECTL) wait provider.pkg $(PROJECT_NAME) --for condition=Healthy --for condition=Installed --for=create --timeout 5m
	@$(OK) running locally built provider

e2e: local-deploy chainsaw

# Compare the current schema.json against a schema from a specific provider version.
# Downloads the old provider binary, generates its schema, and diffs the two.
# Usage:
#   make schema-diff OLD_PROVIDER_VERSION=1.0.0
schema-diff: $(TERRAFORM)
	@if [ -z "$(OLD_PROVIDER_VERSION)" ]; then \
		echo "Error: OLD_PROVIDER_VERSION is required. Usage: make schema-diff OLD_PROVIDER_VERSION=1.0.0"; \
		exit 1; \
	fi
	@$(INFO) Comparing provider schema $(OLD_PROVIDER_VERSION) vs $(TERRAFORM_PROVIDER_VERSION)
	@DIFF_OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	DIFF_ARCH=$$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/'); \
	DIFF_PLATFORM="$${DIFF_OS}_$${DIFF_ARCH}"; \
	mkdir -p $(WORK_DIR)/schema-diff/old/$(TERRAFORM_FILE_MIRROR_REPO)/$(TERRAFORM_PROVIDER_SOURCE)/$(OLD_PROVIDER_VERSION)/$${DIFF_PLATFORM}; \
	curl -fsSL $(TERRAFORM_PROVIDER_REPO)/releases/download/v$(OLD_PROVIDER_VERSION)/$(TERRAFORM_PROVIDER_DOWNLOAD_NAME)_$(OLD_PROVIDER_VERSION)_$${DIFF_PLATFORM}.zip \
		-o $(WORK_DIR)/schema-diff/old/terraform-provider.zip; \
	unzip -o -qq $(WORK_DIR)/schema-diff/old/terraform-provider.zip \
		-d $(WORK_DIR)/schema-diff/old/$(TERRAFORM_FILE_MIRROR_REPO)/$(TERRAFORM_PROVIDER_SOURCE)/$(OLD_PROVIDER_VERSION)/$${DIFF_PLATFORM}/; \
	rm -f $(WORK_DIR)/schema-diff/old/terraform-provider.zip; \
	echo '{"terraform":[{"required_providers":[{"provider":{"source":"'"$(TERRAFORM_PROVIDER_SOURCE)"'","version":"'"$(OLD_PROVIDER_VERSION)"'"}}],"required_version":"'"$(TERRAFORM_VERSION)"'"}]}' > $(WORK_DIR)/schema-diff/old/main.tf.json; \
	echo 'provider_installation { filesystem_mirror { path = "$(WORK_DIR)/schema-diff/old/$(TERRAFORM_FILE_MIRROR)" include = ["*/*/*"] } }' > $(WORK_DIR)/schema-diff/old/config.tfrc; \
	TF_CLI_CONFIG_FILE=$(WORK_DIR)/schema-diff/old/config.tfrc $(TERRAFORM) -chdir=$(WORK_DIR)/schema-diff/old init -no-color > $(WORK_DIR)/schema-diff/old/terraform-logs.txt 2>&1; \
	TF_CLI_CONFIG_FILE=$(WORK_DIR)/schema-diff/old/config.tfrc $(TERRAFORM) -chdir=$(WORK_DIR)/schema-diff/old providers schema -json=true > $(WORK_DIR)/schema-diff/old-schema.json 2>> $(WORK_DIR)/schema-diff/old/terraform-logs.txt; \
	echo ""; \
	echo "Comparing schema v$(OLD_PROVIDER_VERSION) -> v$(TERRAFORM_PROVIDER_VERSION):"; \
	echo ""; \
	./scripts/version_diff.py config/generated.lst $(WORK_DIR)/schema-diff/old-schema.json config/schema.json || true
	@$(OK) Comparing provider schema $(OLD_PROVIDER_VERSION) vs $(TERRAFORM_PROVIDER_VERSION)

# Diff the schema.json against the version from the base branch (used in CI).
schema-version-diff:
	@$(INFO) Checking for native state schema version changes
	@export PREV_PROVIDER_VERSION=$$(git cat-file -p "${GITHUB_BASE_REF}:Makefile" | sed -nr 's/^export[[:space:]]*TERRAFORM_PROVIDER_VERSION[[:space:]]*\?=[[:space:]]*(.+)/\1/p'); \
	echo Detected previous Terraform provider version: $${PREV_PROVIDER_VERSION}; \
	echo Current Terraform provider version: $${TERRAFORM_PROVIDER_VERSION}; \
	mkdir -p $(WORK_DIR); \
	git cat-file -p "$${GITHUB_BASE_REF}:config/schema.json" > "$(WORK_DIR)/schema.json.$${PREV_PROVIDER_VERSION}"; \
	./scripts/version_diff.py config/generated.lst "$(WORK_DIR)/schema.json.$${PREV_PROVIDER_VERSION}" config/schema.json
	@$(OK) Checking for native state schema version changes

.PHONY: uptest chainsaw local-deploy e2e submodules cobertura go.cachedir run schema-diff schema-version-diff
