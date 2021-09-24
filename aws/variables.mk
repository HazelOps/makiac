# This file should contain variables used in current module
##################################################################
# main variables
AWS_CLI_VERSION ?= 2.2.0
AWS_MFA_ENABLED ?= false

# ecs variables 
SCALE ?= 3
DOCKERFILE ?= Dockerfile
ECS_DEPLOY_VERSION ?= latest
ENABLE_BUILDKIT ?= 1
DOCKER_BUILD_ADDITIONAL_PARAMS ?=
DOCKER_RUN_ADDITIONAL_PARAMS ?=

# localstack variables
# Actual LOCALSTACK_API_KEY should be set in Makefile
LOCALSTACK_API_KEY ?= 1234567Local
# This can be overriden for different args, like setting an endpoint, like localstack
LOCALSTACK_IMAGE ?= localstack/localstack
LOCALSTACK_VERSION ?= latest
LOCALSTACK_WEB_UI_PORT ?= 8088
LOCALSTACK_PORTS ?= "4510-4620"
LOCALSTACK_SERVICE_LIST ?= "dynamodb,s3,lambda,cloudformation,sts,iam,acm,ec2,route53,ssm,cloudwatch,apigateway,ecs,ecr,events,serverless" #etc. serverless? api-gateway?

# Maximum time for RDS Failover execution, in minutes
RDS_FAILOVER_TIMEOUT ?= 5
# Timeout of RDS Failover check, in seconds
RDS_FAILOVER_LOOP_TIMEOUT ?= 3
# Default suffix for RDS DB Identifier
RDS_DB_SUFFIX ?= APP-DB
