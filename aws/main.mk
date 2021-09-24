# Environment Validation
########################################################################################################################
ifndef AWS_REGION
$(error Please set AWS_REGION via `export AWS_REGION=<aws_region>` or use direnv. This is nessesary for additional tools that are not able to read a region from your AWS profile)
endif

ifeq ($(AWS_MFA_ENABLED),"true")
export AWS_ACCESS_KEY_ID=$(shell echo $(MFA_AWS_ACCESS_KEY_VALUE))
export AWS_SECRET_ACCESS_KEY=$(shell echo $(MFA_AWS_SECRET_ACCESS_KEY_VALUE))
export AWS_SESSION_TOKEN=$(shell echo $(MFA_AWS_SESSION_TOKEN_VALUE))
endif
# Macroses
########################################################################################################################
# We don't check for AWS_PROFILE, but instead we assume the profile name.
# You can override it, although it's recommended to have a profile per environment in your ~/.aws/credentials
AWS_PROFILE ?= $(NAMESPACE)-$(ENV)
AWS_CLI_PROFILE ?= $(shell echo $$(if [ "$(AWS_MFA_ENABLED)" = "true" ]; then echo ""; else echo "--profile $(AWS_PROFILE)"; fi))
AWS_USER ?= $(shell [ -f ~/.aws/credentials ] && $(AWS) iam get-user | $(JQ) -r ".User.UserName")
AWS_ACCOUNT ?= $(shell [ -f ~/.aws/credentials ] && $(AWS) sts get-caller-identity | $(JQ) -r '.Account' || echo "nil" )

AWS_DEV_ENV_NAME ?= $(shell [ -f ~/.aws/credentials ] && $(AWS) iam list-user-tags --user-name $(AWS_USER) | ( $(JQ) -e -r '.Tags[] | select(.Key == "devEnvironmentName").Value') || echo "$(ENV) (User env is not configured)")

# AWS MFA
MFA_DEVICE_ARN ?= 
MFA_TOKEN_CODE ?= $(eval MFA_TOKEN_CODE := $(shell bash -c 'read -p "Enter MFA token: " token; echo $$token'))$(MFA_TOKEN_CODE)
MFA_GET_SESSION_TOKEN ?= $(eval MFA_GET_SESSION_TOKEN := $(shell echo $$(aws sts get-session-token --serial-number ${MFA_DEVICE_ARN} --token-code $(MFA_TOKEN_CODE) | $(JQ) 'map_values(tostring)' | $(JQ) .Credentials)))$(MFA_GET_SESSION_TOKEN)
MFA_AWS_ACCESS_KEY_ID ?= $(shell echo $(MFA_GET_SESSION_TOKEN) | $(JQ) .AccessKeyId | xargs > ~/.aws/mfa_aws_access_key)
MFA_AWS_SECRET_ACCESS_KEY ?= $(shell echo $(MFA_GET_SESSION_TOKEN) | $(JQ) .SecretAccessKey | xargs > ~/.aws/mfa_aws_secret_access_key)
MFA_AWS_SESSION_TOKEN ?= $(shell echo $(MFA_GET_SESSION_TOKEN) | $(JQ) .SessionToken | xargs > ~/.aws/mfa_aws_session_token)
MFA_AWS_EXPIRATION ?= $(shell echo $(MFA_GET_SESSION_TOKEN) | $(JQ) .Expiration | xargs)

MFA_AWS_ACCESS_KEY_VALUE ?= $(shell echo $$(if [ "$(AWS_MFA_ENABLED)" = "true" ]; then cat ~/.aws/mfa_aws_access_key; else echo ""; fi)) #$$(cat ~/.aws/mfa_aws_access_key)
MFA_AWS_SECRET_ACCESS_KEY_VALUE ?= $(shell echo $$(if [ "$(AWS_MFA_ENABLED)" = "true" ]; then cat ~/.aws/mfa_aws_secret_access_key; else echo ""; fi)) #$$(cat ~/.aws/mfa_aws_secret_access_key)
MFA_AWS_SESSION_TOKEN_VALUE ?= $(shell echo $$(if [ "$(AWS_MFA_ENABLED)" = "true" ]; then cat ~/.aws/mfa_aws_session_token; else echo ""; fi)) #$$(cat ~/.aws/mfa_aws_session_token)


# $(AWS_ARGS) definition see in .infra/icmk/aws/localstack.mk
AWS_ARM ?= $(shell echo $$(if [ "$(AWS_MFA_ENABLED)" = "true" ]; then echo "$(AWS_ARM_WITH_MFA)"; else echo "$(AWS_ARM_NO_MFA)"; fi))
AWS_ARM_WITH_MFA ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" --platform "linux/amd64" \
	-v $(HOME)/.aws/:/.aws \
	-i \
	-e AWS_PROFILE="$(AWS_PROFILE)" \
	-e AWS_REGION="$(AWS_REGION)" \
	-e AWS_ACCESS_KEY_ID="$(MFA_AWS_ACCESS_KEY_VALUE)" \
	-e AWS_SECRET_ACCESS_KEY="$(MFA_AWS_SECRET_ACCESS_KEY_VALUE)" \
	-e AWS_SESSION_TOKEN="$(MFA_AWS_SESSION_TOKEN_VALUE)" \
	-e AWS_CONFIG_FILE="/.aws/config" \
	-e AWS_SHARED_CREDENTIALS_FILE="/.aws/credentials" \
	amazon/aws-cli:$(AWS_CLI_VERSION) $(AWS_ARGS)

AWS_ARM_NO_MFA ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" --platform "linux/amd64" \
	-v $(HOME)/.aws/:/.aws \
	-i \
	-e AWS_PROFILE="$(AWS_PROFILE)" \
	-e AWS_REGION="$(AWS_REGION)" \
	-e AWS_CONFIG_FILE="/.aws/config" \
	-e AWS_SHARED_CREDENTIALS_FILE="/.aws/credentials" \
	amazon/aws-cli:$(AWS_CLI_VERSION) $(AWS_ARGS)


AWS_DEFAULT ?= $(shell echo $$(if [ "$(AWS_MFA_ENABLED)" = "true" ]; then echo "$(AWS_DEFAULT_WITH_MFA)"; else echo "$(AWS_DEFAULT_NO_MFA)"; fi))
AWS_DEFAULT_WITH_MFA ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" \
	-v $(HOME)/.aws/:/.aws \
	-i \
	-e AWS_PROFILE="$(AWS_PROFILE)" \
	-e AWS_REGION="$(AWS_REGION)" \
	-e AWS_ACCESS_KEY_ID="$(MFA_AWS_ACCESS_KEY_VALUE)" \
	-e AWS_SECRET_ACCESS_KEY="$(MFA_AWS_SECRET_ACCESS_KEY_VALUE)" \
	-e AWS_SESSION_TOKEN="$(MFA_AWS_SESSION_TOKEN_VALUE)" \
	-e AWS_CONFIG_FILE="/.aws/config" \
	-e AWS_SHARED_CREDENTIALS_FILE="/.aws/credentials" \
	amazon/aws-cli:$(AWS_CLI_VERSION) $(AWS_ARGS)

AWS_DEFAULT_NO_MFA ?= $(DOCKER) run --user "$(CURRENT_USER_ID):$(CURRENT_USERGROUP_ID)" \
	-v $(HOME)/.aws/:/.aws \
	-i \
	-e AWS_PROFILE="$(AWS_PROFILE)" \
	-e AWS_REGION="$(AWS_REGION)" \
	-e AWS_CONFIG_FILE="/.aws/config" \
	-e AWS_SHARED_CREDENTIALS_FILE="/.aws/credentials" \
	amazon/aws-cli:$(AWS_CLI_VERSION) $(AWS_ARGS)

AWS ?= $(shell echo $$(if [ "$(LINUX_ARCH)" = "arm64" ]; then echo "$(AWS_ARM)"; else echo "$(AWS_DEFAULT)"; fi))

CMD_AWS_LOGS_TAIL = @$(AWS) logs tail $(SERVICE_NAME) --follow --format "short"
CMD_AWS_EC2_IMPORT_KEY_PAIR = @$(AWS) ec2 import-key-pair  --key-name="$(EC2_KEY_PAIR_NAME)" --public-key-material="$(SSH_PUBLIC_KEY_BASE64)"


aws.mfa:
	$(MFA_AWS_ACCESS_KEY_ID)
	$(MFA_AWS_SECRET_ACCESS_KEY)
	$(MFA_AWS_SESSION_TOKEN)
	@echo "\033[36mMFA Token will be expired at:\033[0m $(MFA_AWS_EXPIRATION)"


# Getting OS|Linux info
OS_NAME ?= $(shell uname -s)
LINUX_OS_DISTRIB ?= $$(cat /etc/issue)
LINUX_ARCH ?= $(shell uname -m)
LINUX_BITS ?= $(shell uname -m | sed 's/x86_//;s/i[3-6]86/32/')
ARCH ?= $$(echo $$(if echo "$(LINUX_ARCH)" | grep -Fqe "arm"; then echo "arm$(LINUX_BITS)"; else echo "$(LINUX_BITS)bit"; fi))
LINUX_DISTRIB_TEMP ?= $$(echo $$(if echo "$(LINUX_OS_DISTRIB)" | grep -Fqe "Ubuntu"; then echo "ubuntu"; elif echo "$(LINUX_OS_DISTRIB)" | grep -Fqe "Debian"; then echo "ubuntu"; else echo "linux"; fi))
LINUX_DISTRIB ?= $$(echo $(LINUX_DISTRIB_TEMP) | xargs)
LINUX_PACKAGE_EXT ?= $$(echo $$(if echo "$(LINUX_OS_DISTRIB)" | grep -Fqe "Ubuntu"; then echo ".deb"; elif echo "$(LINUX_OS_DISTRIB)" | grep -Fqe "Debian"; then echo ".deb"; else echo ".rpm"; fi))
# Download Session Manager cmds
SSM_DOWNLOAD_FOR_MAC_OS ?= curl -s "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" > "sessionmanager-bundle.zip" && unzip -qq sessionmanager-bundle.zip
SSM_DOWNLOAD_FOR_LINUX_OS ?= curl -s "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/$(LINUX_DISTRIB)_$(ARCH)/session-manager-plugin$(LINUX_PACKAGE_EXT)" > "session-manager-plugin$(LINUX_PACKAGE_EXT)"
CMD_SSM_DOWNLOAD ?= $(shell echo $$(if [ "$(OS_NAME)" = "Linux" ]; then echo "$(SSM_DOWNLOAD_FOR_LINUX_OS)"; else echo "$(SSM_DOWNLOAD_FOR_MAC_OS)"; fi))
# Installation Session Manager cmds
LINUX_INSTALLER ?= $$(echo $$(if echo "$(LINUX_OS_DISTRIB)" | grep -Fqe "Ubuntu"; then echo "sudo dpkg -i"; elif echo "$(LINUX_OS_DISTRIB)" | grep -Fqe "Debian"; then echo "sudo dpkg -i"; else echo "sudo yum install -y -q"; fi))
SSM_INSTALL_ON_MAC_OS ?= sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
SSM_INSTALL_ON_LINUX_OS ?= $(LINUX_INSTALLER) session-manager-plugin$(LINUX_PACKAGE_EXT)
CMD_SSM_INSTALL ?= $(shell echo $$(if [ "$(OS_NAME)" = "Linux" ]; then echo "$(SSM_INSTALL_ON_LINUX_OS)"; else echo "$(SSM_INSTALL_ON_MAC_OS)"; fi))
# Cleanup Session Manager installation package
SSM_CLEANUP_ON_MAC_OS ?= rm -rf sessionmanager-bundle sessionmanager-bundle.zip
SSM_CLEANUP_ON_LINUX_OS ?= rm -rf session-manager-plugin$(LINUX_PACKAGE_EXT)
CMD_SSM_CLEANUP ?= $(shell echo $$(if [ "$(OS_NAME)" = "Linux" ]; then echo "$(SSM_CLEANUP_ON_LINUX_OS)"; else echo "$(SSM_CLEANUP_ON_MAC_OS)"; fi))

# SSM access to Fargate ECS
SSM_MI_TARGET ?= $(shell $(AWS) ssm describe-instance-information | $(JQ) -er '.InstanceInformationList[] | select(.Name == "$(SVC)" and .PingStatus == "Online") | .InstanceId' > tmp && cat tmp | head -1 && rm -rf tmp || rm -rf tmp)
# We use local aws-cli here due to interactive actions 
SSM_TO_FARGATE ?= aws $(AWS_CLI_PROFILE) ssm start-session --target $(SSM_MI_TARGET)
CMD_SSM_TO_FARGATE ?= $(shell echo $$(if [ -z "$(SSM_MI_TARGET)" ]; then echo "echo '[ERROR] SSM mi target is not available now (please try in a minute) or not configured. Exit.'"; else echo "$(SSM_TO_FARGATE)"; fi))
# Tasks
########################################################################################################################
aws.debug: ## Show environment information for debug purposes
	@echo "\033[32m=== AWS Environment Info ===\033[0m"
	@echo "\033[36mAWS_DEV_ENV_NAME\033[0m: $(AWS_DEV_ENV_NAME)"
	@echo "\033[36mAWS_ACCOUNT\033[0m: $(AWS_ACCOUNT)"
	@echo "\033[36mAWS_PROFILE\033[0m: $(AWS_PROFILE)"
	@echo "\033[36mAWS_USER\033[0m: $(AWS_USER)"

os.debug:
	@echo "\033[32m=== System Info ===\033[0m"
	@echo "\033[36mOS_NAME\033[0m: $(OS_NAME)"
	@echo "\033[36mLINUX_ARCH\033[0m: $(LINUX_ARCH)"
	@echo "\033[36mARCH\033[0m: $(ARCH)"

aws.profile:
	$(shell mkdir -p ~/.aws && echo "[$(AWS_PROFILE)]\naws_access_key_id = $(AWS_ACCESS_KEY_ID)\naws_secret_access_key = $(AWS_SECRET_ACCESS_KEY)\nregion = $(AWS_REGION)" >> ~/.aws/credentials)

aws.key-pair: aws.import-ssh-key
aws.import-ssh-key:
	$(CMD_AWS_EC2_IMPORT_KEY_PAIR)

# Install AWS SSM Session Manager plugin
ssm-plugin: ssm-plugin.download ssm-plugin.install ssm-plugin.check
ssm-plugin.download:
	@$(CMD_SSM_DOWNLOAD)
ssm-plugin.install:
	@$(CMD_SSM_INSTALL)
	@$(CMD_SSM_CLEANUP)
ssm-plugin.check:
ifeq (, $(shell which session-manager-plugin))
	@echo "\033[31m[FAILED]\033[0m Your SSM Session Manager Plugin is not installed or incorrectly configured.\n Use \033[33mmake ssm-plugin\033[0m to install it.\n Alternatively you can follow AWS Documentation \033[34mhttps://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html\033[0m \n and install it manually."
else
	@echo "\n\033[32m[OK]\033[0m SSM Session Manager Plugin is installed."
endif

# Dependencies
########################################################################################################################
# TODO: Add validation for ability to connect to AWS
# Ensures aws toolchain is installed
aws:
ifeq (, $(AWS))
	$(error "aws cli toolchain is not installed or incorrectly configured.")
endif
