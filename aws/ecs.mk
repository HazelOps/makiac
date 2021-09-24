# Macroses
########################################################################################################################
TAG ?= $(ENV)
TAG_LATEST ?= $(ENV)-latest

ECS_CLUSTER_NAME ?= $(ENV)-$(NAMESPACE)
ECS_SERVICE_NAME ?= $(SERVICE_NAME)
ECS_TASK_NAME ?= $(ENV)-$(SVC)
DOCKER_REGISTRY ?= $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com
DOCKER_IMAGE_NAME ?= $(NAMESPACE)-$(SVC)
ENABLE_INLINE_CACHE ?= $(ENABLE_BUILDKIT)
ECS_DEPLOY_TIMEOUT ?= 600

ECS_SERVICE_TASK_NETWORK_CONFIG ?= $(shell $(AWS) ssm get-parameter --name "/$(ENV)/terraform-output" --with-decryption | $(JQ) -r '.Parameter.Value' | $(BASE64) -d | $(JQ) -rc '.$(shell echo $(SVC) | sed 's/-/_/g')_task_network_configuration.value')
ECS_SERVICE_TASK_LAUNCH_TYPE ?= $(shell $(AWS) ssm get-parameter --name "/$(ENV)/terraform-output" --with-decryption | $(JQ) -r '.Parameter.Value' | $(BASE64) -d | $(JQ) -rc '.$(shell echo $(SVC) | sed 's/-/_/g')_task_launch_type.value')
SSM_OUTPUT_JSON = $(shell $(AWS) ssm get-parameter --name "/$(ENV)/terraform-output" --with-decryption | $(JQ) -r '.Parameter.Value' | $(BASE64) -d)

# This is required due to a bug in Docker Multistage + Cache configuration.
ECS_SERVICE_DOCKER_BUILD_CACHE_PARAMETER ?= $(shell [ "$(ENABLE_BUILDKIT)" = "1" ] && echo "--cache-from $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG_LATEST)" || echo "" )

ECS_SERVICE_TASK_ID = $(eval ECS_SERVICE_TASK_ID := $(shell $(AWS) ecs run-task --cluster $(ECS_CLUSTER_NAME) --task-definition "$(ECS_SERVICE_TASK_DEFINITION_ARN)" --network-configuration '$(ECS_SERVICE_TASK_NETWORK_CONFIG)' --launch-type "$(ECS_SERVICE_TASK_LAUNCH_TYPE)" | $(JQ) -r '.tasks[].taskArn' | $(REV) | $(CUT) -d'/' -f1 | $(REV)))$(ECS_SERVICE_TASK_ID)
ECS_SERVICE_TASK_DEFINITION_ARN = $(shell $(AWS) ecs describe-task-definition --task-definition $(ECS_TASK_NAME) | $(JQ) -r '.taskDefinition.taskDefinitionArn')

ECS_SERVICE_RUNNING_TASK_ID = $(eval ECS_SERVICE_RUNNING_TASK_ID := $(shell $(AWS) ecs list-tasks --cluster $(ECS_CLUSTER_NAME) --service-name $(ECS_SERVICE_NAME) --desired-status "RUNNING" | $(JQ) -r '.taskArns[]' | $(CUT) -d'/' -f3))$(ECS_SERVICE_RUNNING_TASK_ID)
CMD_SSM_TO_FARGATE_TASK ?= aws ecs $(AWS_CLI_PROFILE) execute-command --cluster $(ECS_CLUSTER_NAME) --task $(ECS_SERVICE_RUNNING_TASK_ID) --container $(SVC) --command "/bin/sh" --interactive

CMD_ECS_SERVICE_DEPLOY = @$(ECS) deploy $(AWS_CLI_PROFILE) $(ECS_CLUSTER_NAME) $(ECS_SERVICE_NAME) --task $(ECS_SERVICE_TASK_DEFINITION_ARN) --image $(SVC) $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG) --diff --timeout $(ECS_DEPLOY_TIMEOUT) --rollback -e $(SVC) DD_VERSION $(TAG)
CMD_ECS_SERVICE_REDEPLOY = @$(ECS) deploy $(AWS_CLI_PROFILE) --region $(AWS_REGION)  $(ECS_CLUSTER_NAME) $(ECS_SERVICE_NAME) --diff --rollback
CMD_ECS_SERVICE_DOCKER_BUILD = DOCKER_BUILDKIT=$(ENABLE_BUILDKIT) $(DOCKER) build \
	. \
	-t $(DOCKER_IMAGE_NAME) \
	-t $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG) \
	-t $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG_LATEST) \
	-f $(PROJECT_PATH)/$(DOCKERFILE) \
	$(ECS_SERVICE_DOCKER_BUILD_CACHE_PARAMETER) \
	--build-arg DOCKER_REGISTRY=$(DOCKER_REGISTRY) \
	--build-arg DOCKER_IMAGE_NAME=$(DOCKER_IMAGE_NAME) \
	--build-arg ENV=$(ENV) \
	--build-arg BUILDKIT_INLINE_CACHE=$(ENABLE_INLINE_CACHE) \
	--build-arg PROJECT_PATH=$(PROJECT_PATH) \
	$(DOCKER_BUILD_ADDITIONAL_PARAMS)

CMD_ECS_SERVICE_DOCKER_PUSH = \
	$(DOCKER) push $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG) && \
	$(DOCKER) push $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG_LATEST)

# Checks every 5 seconds the task status and goes on once task status is not RUNNING
CMD_ECS_SERVICE_TASK_STOP_WAIT = printf "%s" "Task $(ECS_SERVICE_TASK_ID) is running ."; until [ $$($(AWS) ecs describe-tasks --cluster $(ECS_CLUSTER_NAME) --tasks arn:aws:ecs:$(AWS_REGION):$(AWS_ACCOUNT):task/$(ECS_CLUSTER_NAME)/$(ECS_SERVICE_TASK_ID) | jq -r '.tasks[].lastStatus') != RUNNING ]; do printf "%s" "."; sleep 5; done 
# Composes the respective exit code. Event though one of task's containers has non zero exit code macros fails
CMD_ECS_SERVICE_TASK_EXIT_CODE_GET = FLAG=0; $(AWS) ecs describe-tasks --cluster $(ECS_CLUSTER_NAME) --tasks arn:aws:ecs:$(AWS_REGION):$(AWS_ACCOUNT):task/$(ECS_CLUSTER_NAME)/$(ECS_SERVICE_TASK_ID) | jq -r '.tasks[].containers[].exitCode' | while read EXIT_CODE; do if [ "$${EXIT_CODE}" != "0" ]; then printf "%s\n" " stopped with issue"; exit $${EXIT_CODE}; fi; done

CMD_ECS_SERVICE_TASK_LOG = $(ECS_CLI) logs --task-id "$(ECS_SERVICE_TASK_ID)" --cluster "$(ECS_CLUSTER_NAME)" --timestamps
CMD_ECS_SERVICE_TASK_GET_LOG = until echo $$($(ECS_CLI) logs --task-id "$(ECS_SERVICE_TASK_ID)" --cluster "$(ECS_CLUSTER_NAME)" --timestamps) | grep -Fqe "Z "; do sleep 2; done
CMD_ECS_SERVICE_TASK_RUN = @echo "Task $(ECS_SERVICE_TASK_ID) for definition $(ECS_SERVICE_TASK_DEFINITION_ARN) has been started.\nLogs: \n " && $(CMD_ECS_SERVICE_TASK_GET_LOG) && $(CMD_ECS_SERVICE_TASK_LOG) && $(CMD_ECS_SERVICE_TASK_STOP_WAIT) && $(CMD_ECS_SERVICE_TASK_EXIT_CODE_GET)

CMD_ECR_DOCKER_PURGE_CACHE = @echo "Removing '$(TAG_LATEST)' tag from AWS ECR" && $(AWS) ecr batch-delete-image --repository-name $(DOCKER_IMAGE_NAME) --image-ids imageTag=$(TAG_LATEST) | $(JQ) -er 'select(.failures[].failureReason != null) | def yellow: "\u001b[33m"; def reset: "\u001b[0m"; yellow + "[WARNING]:", reset + "\( .failures[].failureReason)"' || echo "\033[32m[OK]\033[0m '$(TAG_LATEST)' tag was removed from AWS ECR"

CMD_ECS_SERVICE_SCALE = @$(ECS) scale $(AWS_CLI_PROFILE) $(ECS_CLUSTER_NAME) $(ECS_TASK_NAME) $(SCALE)
CMD_ECS_SERVICE_DESTROY = echo "Destroy $(SVC) is not implemented"

CMD_ECS_SERVICE_LOCAL_UP = $(ECS_CLI) local up --task-def-remote $(ECS_SERVICE_TASK_DEFINITION_ARN) --force
CMD_ECS_SERVICE_LOCAL_DOWN = $(ECS_CLI) local down --task-def-remote $(ECS_SERVICE_TASK_DEFINITION_ARN)

CMD_ECS_SERVICE_DOCKER_RUN = $(DOCKER) run $(DOCKER_RUN_ADDITIONAL_PARAMS) --rm $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG)

ECS ?= $(DOCKER) run -i --rm -v $(HOME)/.aws/:/root/.aws hazelops/ecs-deploy:$(ECS_DEPLOY_VERSION) ecs
ECS_CLI ?= $(DOCKER) run \
	-i --rm -v /var/run/docker.sock:/var/run/docker.sock \
	-v $(HOME)/.aws/:/root/.aws \
	-e AWS_PROFILE=$(AWS_PROFILE) \
	-e AWS_REGION=$(AWS_REGION) \
	hazelops/ecs-cli

# Tasks
########################################################################################################################
AWS_CLI_ECR_LOGIN ?= $$(echo $$(if echo "$(DOCKER_REGISTRY)" | grep -Fqe "public"; then echo "ecr-public"; else echo "ecr"; fi))
ecr.login: aws
	@echo $(shell $(AWS) $(AWS_CLI_ECR_LOGIN) get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(DOCKER_REGISTRY))

# Dependencies
########################################################################################################################
# Ensures ecs-deploy is installed
ecs:
ifeq (, $(ECS))
	$(error "ecs-deploy is not installed or incorrectly configured. Run \\n`pip install ecs-deploy`. More info: https://github.com/fabfuel/ecs-deploy")
endif

# Ensures ecs-cli is installed
ecs-cli:
ifeq (, $(ECS_CLI))
	$(error "AWS ecs-cli is not installed or incorrectly configured." )
endif

# Backwards Compatibility, should be removed in 2.0
########################################################################################################################
CMD_SERVICE_DEPLOY = $(CMD_ECS_SERVICE_DEPLOY)
CMD_SERVICE_REDEPLOY = $(CMD_ECS_SERVICE_REDEPLOY)
CMD_SERVICE_DOCKER_BUILD = $(CMD_ECS_SERVICE_DOCKER_BUILD)
CMD_SERVICE_DOCKER_PUSH = $(CMD_ECS_SERVICE_DOCKER_PUSH)
CMD_SERVICE_TASK_RUN = $(CMD_ECS_SERVICE_TASK_RUN)
CMD_SERVICE_SCALE = $(CMD_ECS_SERVICE_SCALE)
CMD_SERVICE_DESTROY = $(CMD_ECS_SERVICE_DESTROY)
CMD_SERVICE_LOCAL_UP =$(CMD_ECS_SERVICE_LOCAL_UP)
CMD_SERVICE_LOCAL_DOWN = $(CMD_ECS_SERVICE_LOCAL_DOWN)
CMD_SERVICE_BIN = $(CMD_ECS_SERVICE_BIN)
