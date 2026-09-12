# Makefile for Ravion Modules

.PHONY: help test test-charts test-vpc test-alb test-nlb test-sg test-ecs test-elasticache test-s3 test-cleanup test-cleanup-dry clean fmt validate deps test-single test-ecs-cluster test-ecs-service test-eks-service list-tests modules-tools-build publish-local-dev pull-local-definition readme env-local-sh env-local-fish

TIMEOUT ?= 180m
PARALLEL ?= 3
TEST_DIR := ./test
FILTER ?=
MODULE_TOOLS_DIR := tools/ravion-modules
ENV_LOCAL ?= .env.local
LOCAL_DEV_PUBLISH_FLAGS :=
PULL_SOURCE_TYPE ?= rvn-aws-rds
PULL_TARGET_TYPE ?= rvn-rds
PULL_OUTPUT ?= database/rds/rvn-rds-definition.yml
PULL_VERSION_FLAG :=
ifneq ($(PULL_VERSION),)
PULL_VERSION_FLAG := --version "$(PULL_VERSION)"
endif
ifeq ($(DRY_RUN),1)
LOCAL_DEV_PUBLISH_FLAGS += --dry-run
endif
ifeq ($(FORCE),1)
LOCAL_DEV_PUBLISH_FLAGS += --force
endif
LOCAL_DEV_SOURCE_REF_ENV :=
ifneq ($(SOURCE_REF),)
LOCAL_DEV_SOURCE_REF_ENV := RAVION_LOCAL_DEV_SOURCE_REF="$(SOURCE_REF)"
endif
LOAD_ENV_LOCAL = if [ -f "$(ENV_LOCAL)" ]; then set -a; . "$(ENV_LOCAL)"; set +a; fi;

# Test runner function: $(1)=timeout, $(2)=parallel, $(3)=test args
# Outputs formatted test results in real-time and saves JSON log to test.log
define run_test
	@cd $(TEST_DIR) && rm -f test.log && set -euo pipefail && go test -json -v -timeout $(1) -parallel $(2) $(3) 2>&1 | tee test.log | gotestfmt
endef

help:
	@echo "Usage: make [target] [TIMEOUT=60m] [PARALLEL=2]"
	@echo ""
	@echo "Test Targets:"
	@echo "  test                 Run all integration tests"
	@echo "  test-single          Run a single test (TEST=TestName required)"
	@echo "  test-vpc             Run VPC module tests"
	@echo "  test-alb             Run ALB module tests"
	@echo "  test-nlb             Run NLB module tests"
	@echo "  test-sg              Run Security Group tests"
	@echo "  test-ecs             Run all ECS tests"
	@echo "  test-ecs-cluster     Run ECS Cluster tests"
	@echo "  test-ecs-service     Run ECS Service tests"
	@echo "  test-eks-service     Run EKS Service tests"
	@echo "  test-elasticache     Run ElastiCache tests"
	@echo "  test-s3              Run S3 module tests"
	@echo "  test-charts          Run Helm chart lint + template tests (no cluster needed)"
	@echo ""
	@echo "Cleanup Targets:"
	@echo "  test-cleanup         Clean up orphaned test resources"
	@echo "  test-cleanup-dry     Dry run - show what would be cleaned"
	@echo "  clean                Remove test artifacts and state files"
	@echo ""
	@echo "Utility Targets:"
	@echo "  deps                 Download Go dependencies"
	@echo "  fmt                  Format all Terraform files"
	@echo "  validate             Validate all modules"
	@echo "  list-tests           List all available tests"
	@echo "  modules-tools-build  Build module definition tooling"
	@echo "  publish-local-dev    Publish one module to local dev API (MODULE=module type, file name, or path required)"
	@echo "  pull-local-definition Pull one module definition from local dev API into an authoring YAML file"
	@echo "  readme               Refresh the README module definitions table from definition release versions"
	@echo "  env-local-sh         Print sh/bash/zsh commands for loading .env.local"
	@echo "  env-local-fish       Print fish commands for loading .env.local"
	@echo ""
	@echo "Examples:"
	@echo "  make test                        # Run all tests"
	@echo "  make test FILTER='TestA|TestB'   # Run filtered tests"
	@echo "  make test PARALLEL=1             # Run tests sequentially"
	@echo "  make test-vpc TIMEOUT=30m        # Run VPC tests"
	@echo "  make test-single TEST=TestVpcBasic"
	@echo "  make test-charts"
	@echo "  make test-charts CHART=rvn-eks-web"
	@echo "  make publish-local-dev MODULE=rvn-aws-network"
	@echo "  make publish-local-dev MODULE=rvn-aws-network DRY_RUN=1"
	@echo "  make publish-local-dev MODULE=rvn-aws-network FORCE=1"
	@echo "  make publish-local-dev MODULE=rvn-aws-network SOURCE_REF=my-branch"
	@echo "  make pull-local-definition"
	@echo "  make pull-local-definition PULL_SOURCE_TYPE=rvn-aws-rds PULL_TARGET_TYPE=rvn-rds PULL_OUTPUT=database/rds/rvn-rds-definition.yml"
	@echo "  make pull-local-definition PULL_VERSION=0.0.10"
	@echo "  eval (make env-local-fish)       # fish"
	@printf '%s\n' '  eval "$$(make env-local-sh)"     # sh/bash/zsh'

deps:
	@echo "Downloading Go dependencies..."
	@cd $(TEST_DIR) && go mod download
	@echo "Installing gotestfmt..."
	@go install github.com/gotesttools/gotestfmt/v2/cmd/gotestfmt@latest
	@echo "Dependencies downloaded"

modules-tools-build:
	@echo "Building module definition tooling..."
	@cd $(MODULE_TOOLS_DIR) && npx tsc
	@echo "Module definition tooling built"

publish-local-dev: modules-tools-build
ifndef MODULE
	$(error MODULE is required. Usage: make publish-local-dev MODULE=rvn-aws-network)
endif
	@echo "Publishing $(MODULE) to local dev API..."
	@$(LOAD_ENV_LOCAL) $(LOCAL_DEV_SOURCE_REF_ENV) node $(MODULE_TOOLS_DIR)/dist/src/cli.js publish $(MODULE) --local-dev --format markdown $(LOCAL_DEV_PUBLISH_FLAGS)

pull-local-definition: modules-tools-build
	@echo "Pulling $(PULL_SOURCE_TYPE) from local dev API into $(PULL_OUTPUT) as $(PULL_TARGET_TYPE)..."
	@$(LOAD_ENV_LOCAL) node $(MODULE_TOOLS_DIR)/dist/src/cli.js pull-definition --local-dev --source-type "$(PULL_SOURCE_TYPE)" --target-type "$(PULL_TARGET_TYPE)" --output "$(PULL_OUTPUT)" $(PULL_VERSION_FLAG)

readme: modules-tools-build
	@echo "Refreshing README module definitions table..."
	@node $(MODULE_TOOLS_DIR)/dist/src/cli.js readme

env-local-sh:
	@node -e 'const fs=require("node:fs"); const path=process.env.ENV_LOCAL||"$(ENV_LOCAL)"; if(!fs.existsSync(path)) process.exit(0); for (const line of fs.readFileSync(path,"utf8").split(/\r?\n/)) { const trimmed=line.trim(); if(!trimmed||trimmed.startsWith("#")) continue; const index=trimmed.indexOf("="); if(index<1) continue; const key=trimmed.slice(0,index).trim(); const value=trimmed.slice(index+1).trim().replace(/^(["'"'"'])(.*)\1$$/,"$$2"); if(!/^[A-Za-z_][A-Za-z0-9_]*$$/.test(key)) continue; console.log(`export ${key}=${JSON.stringify(value)}`); }'

env-local-fish:
	@node -e 'const fs=require("node:fs"); const path=process.env.ENV_LOCAL||"$(ENV_LOCAL)"; if(!fs.existsSync(path)) process.exit(0); for (const line of fs.readFileSync(path,"utf8").split(/\r?\n/)) { const trimmed=line.trim(); if(!trimmed||trimmed.startsWith("#")) continue; const index=trimmed.indexOf("="); if(index<1) continue; const key=trimmed.slice(0,index).trim(); const value=trimmed.slice(index+1).trim().replace(/^(["'"'"'])(.*)\1$$/,"$$2"); if(!/^[A-Za-z_][A-Za-z0-9_]*$$/.test(key)) continue; console.log(`set -gx ${key} ${JSON.stringify(value)}`); }'

test:
ifdef FILTER
	@echo "Running filtered tests: $(FILTER) (timeout=$(TIMEOUT), parallel=$(PARALLEL))..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run '$(FILTER)' ./...)
else
	@echo "Running all tests (timeout=$(TIMEOUT), parallel=$(PARALLEL))..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),./...)
endif

test-single:
ifndef TEST
	$(error TEST is required. Usage: make test-single TEST=TestVpcBasic)
endif
	@echo "Running test: $(TEST)..."
	$(call run_test,$(TIMEOUT),1,-run $(TEST) ./...)

test-vpc:
	@echo "Running VPC tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestVpc ./...)

test-alb:
	@echo "Running ALB tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestAlb ./...)

test-nlb:
	@echo "Running NLB tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestNlb ./...)

test-sg:
	@echo "Running Security Group tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestSecurityGroup ./...)

test-ecs:
	@echo "Running ECS tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestEcs ./...)

test-ecs-cluster:
	@echo "Running ECS Cluster tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestEcsCluster ./...)

test-ecs-service:
	@echo "Running ECS Service tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestEcsService ./...)

test-eks-service:
	@echo "Running EKS Service tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestEksService ./...)

test-elasticache:
	@echo "Running ElastiCache tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestElastiCache ./...)

test-s3:
	@echo "Running S3 tests..."
	$(call run_test,$(TIMEOUT),$(PARALLEL),-run TestS3 ./...)

test-charts:
	@echo "Running Helm chart lint + template tests..."
	@./charts/test.sh $(CHART)

test-cleanup:
	@echo "Cleaning up orphaned terratest resources..."
	$(call run_test,30m,1,-run 'TestCleanupOrphanedResources$$' ./...)

test-cleanup-dry:
	@echo "Dry run: Finding orphaned terratest resources..."
	$(call run_test,30m,1,-run TestCleanupOrphanedResourcesDryRun ./...)

fmt:
	@echo "Formatting Terraform files..."
	tofu fmt -recursive
	@echo "Formatting complete"

validate:
	@echo "Validating modules..."
	@for dir in $$(find . -name "*.tf" -exec dirname {} \; | sort -u | grep -v "\.terraform" | grep -v "test/fixtures"); do \
		if [ -f "$$dir/versions.tf" ]; then \
			echo "Validating $$dir..."; \
			(cd "$$dir" && tofu init -backend=false > /dev/null 2>&1 && tofu validate) || exit 1; \
		fi \
	done
	@echo "All modules valid"

clean:
	@echo "Cleaning up test artifacts..."
	rm -f $(TEST_DIR)/test.log
	rm -f $(TEST_DIR)/test-results.json
	find $(TEST_DIR)/fixtures -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find $(TEST_DIR)/fixtures -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	find $(TEST_DIR)/fixtures -name "terraform.tfstate*" -delete 2>/dev/null || true
	@echo "Cleanup complete"

list-tests:
	@echo "Available tests:"
	@cd $(TEST_DIR) && go test -list '.*' ./... 2>/dev/null | grep -E '^Test' | sort
