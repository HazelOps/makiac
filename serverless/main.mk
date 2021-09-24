# Docker executors
########################################################################################################################
SLS ?= @$(DOCKER) run --rm \
	--user root:root \
	--workdir=/app \
	--entrypoint="/usr/local/bin/npx" \
	-e AWS_PROFILE=$(AWS_PROFILE) \
	-e LOCALSTACK_HOST=$(LOCALSTACK_HOST) \
	-e SLS_DEBUG='$(SLS_DEBUG)' \
	-e SLS_DEPRECATION_DISABLE='$(SLS_DEPRECATION_DISABLE)' \
	-e SLS_WARNING_DISABLE='$(SLS_WARNING_DISABLE)' \
	-v ~/.aws/:/root/.aws:ro \
	-v $(ROOT_DIR)/$(PROJECT_PATH):/app \
	-v $(ROOT_DIR)/$(PROJECT_PATH)/.serverless/:/root/.serverless \
	-v $(ROOT_DIR)/.npm/:/root/.npm \
	-v $(SLS_NODE_MODULES_CACHE_MOUNT):/app/node_modules \
	node:$(NODE_VERSION) serverless

NPM ?= @$(DOCKER) run --rm \
	--user root:root \
	--workdir=/app \
	-v $(ROOT_DIR)/$(PROJECT_PATH):/app \
	-v $(ROOT_DIR)/$(PROJECT_PATH)/.config/:/root/.config \
	-v $(ROOT_DIR)/.npm/:/root/.npm \
	-v $(SLS_NODE_MODULES_CACHE_MOUNT):/app/node_modules \
	node:$(NODE_VERSION) npm

# Serverless CLI Reference
########################################################################################################################
CMD_SLS_SERVICE_INSTALL = $(NPM) install --save-dev
CMD_SLS_SERVICE_DEPLOY = $(SLS) deploy --config $(SLS_FILE) --service $(SVC) --verbose --region $(AWS_REGION) --env $(ENV) $(AWS_CLI_PROFILE)
CMD_SLS_SERVICE_INVOKE = $(SLS) invoke --function $(SVC) --path $(EVENT_FILE) --log --config $(SLS_FILE) --service $(SVC) --region $(AWS_REGION) --env $(ENV) $(AWS_CLI_PROFILE)
CMD_SLS_SERVICE_DESTROY = $(SLS) remove --config $(SLS_FILE) --service $(SVC) --verbose --region $(AWS_REGION) --env $(ENV) $(AWS_CLI_PROFILE) || true
CMD_SLS_SERVICE_BUILD = cd $(ROOT_DIR)/$(PROJECT_PATH) && make
CMD_SLS_SERVICE_SECRETS_PUSH = $(CMD_SERVICE_SECRETS_PUSH)
CMD_SLS_SERVICE_SECRETS_PULL = $(CMD_SERVICE_SECRETS_PULL)
# This works with "serverless-domain-manager" plugin and provide domain creation and remove
CMD_SLS_SERVICE_CREATE_DOMAIN = $(SLS) create_domain --verbose --region $(AWS_REGION) --env $(ENV) $(AWS_CLI_PROFILE)
CMD_SLS_SERVICE_DELETE_DOMAIN = $(SLS) delete_domain --verbose --region $(AWS_REGION) --env $(ENV) $(AWS_CLI_PROFILE)

# Tasks
########################################################################################################################


# Dependencies
########################################################################################################################
# Ensures aws toolchain is installed
aws:
ifeq (, $(SLS))
	$(error "aws cli toolchain is not installed or incorrectly configured.")
endif
