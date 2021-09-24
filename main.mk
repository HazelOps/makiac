# Environment Validation
########################################################################################################################
# Ensure ENV is set
ifndef ENV
$(error Please set ENV via `export ENV=<env_name>` or use direnv)
endif


-include $(INFRA_DIR)/env/$(ENV)/*.mk
-include $(INFRA_DIR)/projects/*.mk
include $(INFRA_DIR)/icmk/*/*.mk

# Macroses
########################################################################################################################
# Makefile Helpers
# Get Service name. We're parsing Make task name and extracting SVC. So foo.bar or baz/foo.bar will result to SVC=foo
SVC = $(shell echo $(@) | grep $(SLASHSIGN) > /dev/null && echo $$(echo $(@) | $(CUT) -d/ -f2 | $(CUT) -d. -f1) || echo $$(echo $(@) | $(CUT) -d. -f1))
SVC_TYPE = $(shell echo $(SVC) | $(CUT) -d- -f1 )

ICMK_TEMPLATE_TERRAFORM_BACKEND_CONFIG = $(INFRA_DIR)/icmk/terraform/templates/backend.tf.gotmpl
ICMK_TEMPLATE_TERRAFORM_VARS = $(INFRA_DIR)/icmk/terraform/templates/terraform.tfvars.gotmpl
ICMK_TEMPLATE_TERRAFORM_TFPLAN = $(INFRA_DIR)/icmk/terraform/templates/terraform.tfplan.gotmpl

ICMK_TEMPLATE_WAYPOINT_VARS = $(INFRA_DIR)/icmk/waypoint/templates/waypoint.wpvars.gotmpl

# We are using a tag from AWS User which would tell us which environment this user is using. You can always override it.
ENV ?= $(AWS_DEV_ENV_NAME)
ENV_DIR ?= $(INFRA_DIR)/env/$(ENV)

# Support for stack/tier workspace paths
ifneq (,$(TIER))
	ifneq (,$(STACK))
		ENV_DIR:=$(ENV_DIR)/$(STACK)/$(TIER)
		TERRAFORM_STATE_KEY=$(ENV)/$(STACK)/$(TIER)/terraform.tfstate
		-include $(INFRA_DIR)/env/$(ENV)/$(STACK)/$(TIER)/*.mk
	else
		ENV_DIR:=$(ENV_DIR)/$(TIER)
		TERRAFORM_STATE_KEY=$(ENV)/$(TIER)/terraform.tfstate
		-include $(INFRA_DIR)/env/$(ENV)/$(TIER)/*.mk
	endif
endif

# Get Service sub-directory name in "projects" folder. We're parsing Make task name and extracting PROJECT_SUB_DIR. So baz/foo.bar will result to PROJECT_SUB_DIR=baz
PROJECT_SUB_DIR =  $(shell echo $(@) | grep $(SLASHSIGN) > /dev/null && echo $$(echo $(@) | $(CUT) -d/ -f1)$(SLASHSIGN) || echo "")
PROJECT_ROOT = projects/$(PROJECT_SUB_DIR)
PROJECT_PATH_ABS=$(shell cd $(PROJECT_ROOT)$(SVC) && pwd -P)
PROJECT_PATH = $(PROJECT_ROOT)$(shell basename $(PROJECT_PATH_ABS))
SERVICE_NAME ?= $(ENV)-$(SVC)
# Tasks
########################################################################################################################
.PHONY: auth help
all: help

env.debug: prereqs icmk.debug os.debug aws.debug
icmk.debug:
	@echo "\033[32m=== ICMK Info ===\033[0m"
	@echo "\033[36mENV\033[0m: $(ENV)"
	@echo "\033[36mTAG\033[0m: $(TAG)"
	@echo "\033[36mINFRA_DIR\033[0m: $(INFRA_DIR)"
	@echo "\033[36mPWD\033[0m: $(PWD)"
	@echo "\033[36mICMK_VERSION\033[0m: $(ICMK_VERSION)"
	@echo "\033[36mICMK_GIT_REVISION\033[0m: $(ICMK_GIT_REVISION)"
	@echo "\033[36mENV_DIR\033[0m: $(ENV_DIR)"


up: docker
	# TODO: This should probably use individual apps "up" definitions
	echo "TODO: aws ecs local up"

login: ecr.login ## Perform all required authentication (ECR)
auth: ecr.login
help: ## Display this help screen (default)
	@echo "\033[32m=== Available Tasks ===\033[0m"
	@grep -h -E '^([a-zA-Z_-]|\.)+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

env: env.use
use: env.use
plan: terraform.plan

# Verification of README existing
README_FILE ?= $(PROJECT_ROOT)$(SVC)/README.md
README_FILE_1SYMBOL ?= $$(cat $(README_FILE) | head -n 1 | head -c 1)
README ?= @$$([ -f $(README_FILE) ]) && $$([ "$(README_FILE_1SYMBOL)" = "$(HASHSIGN)" ]) && echo "\033[32m[OK]\033[0m README exists" || echo "\033[31m[FAILED]\033[0m README does not exist. Please describe your project in README.md."

## Tool Dependencies
COMPOSE ?= $(shell which docker-compose)

JQ_ARM ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" --platform "linux/amd64" -v $(INFRA_DIR):$(INFRA_DIR) -i --rm colstrom/jq
JQ_DEFAULT ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" -v $(INFRA_DIR):$(INFRA_DIR) -i --rm colstrom/jq
JQ ?= $(shell echo $$(if [ "$(LINUX_ARCH)" = "arm64" ]; then echo "$(JQ_ARM)"; else echo "$(JQ_DEFAULT)"; fi))
BASE64_ARM ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" --platform "linux/amd64" -i --rm busybox:$(BUSYBOX_VERSION) base64
BASE64_DEFAULT ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" -i --rm busybox:$(BUSYBOX_VERSION) base64
BASE64 ?= $(shell echo $$(if [ "$(LINUX_ARCH)" = "arm64" ]; then echo "$(BASE64_ARM)"; else echo "$(BASE64_DEFAULT)"; fi))
CUT ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" -i --rm busybox:$(BUSYBOX_VERSION) cut
REV ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" -i --rm busybox:$(BUSYBOX_VERSION) rev
AWK ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" -i --rm busybox:$(BUSYBOX_VERSION) awk


GOMPLATE ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" \
	-e ENV="$(ENV)" \
	-e AWS_PROFILE="$(AWS_PROFILE)" \
	-e AWS_REGION="$(AWS_REGION)" \
	-e NAMESPACE="$(NAMESPACE)" \
	-e ROOT_DIR="$(ROOT_DIR)" \
	-e EC2_KEY_PAIR_NAME="$(EC2_KEY_PAIR_NAME)" \
	-e TAG="$(TAG)" \
	-e SSH_PUBLIC_KEY="$(SSH_PUBLIC_KEY)" \
	-e DOCKER_REGISTRY="$(DOCKER_REGISTRY)" \
	-e LOCALSTACK_ENDPOINT=$(LOCALSTACK_ENDPOINT) \
	-e TERRAFORM_AWS_PROVIDER_VERSION=$(TERRAFORM_AWS_PROVIDER_VERSION) \
	-e TERRAFORM_STATE_BUCKET_NAME="$(TERRAFORM_STATE_BUCKET_NAME)" \
	-e TERRAFORM_STATE_KEY="$(TERRAFORM_STATE_KEY)" \
	-e TERRAFORM_STATE_REGION="$(TERRAFORM_STATE_REGION)" \
	-e TERRAFORM_STATE_PROFILE="$(TERRAFORM_STATE_PROFILE)" \
	-e TERRAFORM_STATE_DYNAMODB_TABLE="$(TERRAFORM_STATE_DYNAMODB_TABLE)" \
	-e SHORT_SHA="$(SHORT_SHA)" \
	-e COMMIT_MESSAGE="$(COMMIT_MESSAGE)" \
	-e GITHUB_ACTOR="$(GITHUB_ACTOR)" \
	-v $(ENV_DIR):/temp \
	--rm -i hairyhenderson/gomplate

ECHO = @echo

# Dependencies
########################################################################################################################
# Ensures docker-compose is installed - does not enforce.
docker-compose: docker
ifeq (, $(COMPOSE))
	$(error "docker-compose is not installed or incorrectly configured.")
#else
#	@$(COMPOSE) --version
endif

# Ensures gomplate is installed
gomplate:
ifeq (, $(GOMPLATE))
	$(error "gomplate is not installed or incorrectly configured. https://github.com/hairyhenderson/gomplate")
endif

# Ensures jq is installed
jq:
ifeq (, $(JQ))
	$(error "jq is not installed or incorrectly configured.")
endif
