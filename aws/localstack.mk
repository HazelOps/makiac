# Macroses
########################################################################################################################
LOCALSTACK_HOST ?= $(LOCALSTACK_CONTAINER_IP)
LOCALSTACK_ENDPOINT ?= http://$(LOCALSTACK_HOST):4566

CMD_LOCALSTACK_UP ?= @ ( $(DOCKER) run -d --name localstack -p $(LOCALSTACK_WEB_UI_PORT):$(LOCALSTACK_WEB_UI_PORT) \
	-p $(LOCALSTACK_PORTS):$(LOCALSTACK_PORTS) \
	-p 53:53 \
	-p 443:443 \
	-e LOCALSTACK_API_KEY=$(LOCALSTACK_API_KEY) \
	-e DEBUG=1 \
	-e SERVICES=$(LOCALSTACK_SERVICE_LIST) \
	-e DATA_DIR=/tmp/localstack/data \
	-e PORT_WEB_UI=$(LOCALSTACK_WEB_UI_PORT) \
	-e DOCKER_HOST=unix:///var/run/docker.sock \
	-v /tmp/localstack:/tmp/localstack \
	$(LOCALSTACK_IMAGE):$(LOCALSTACK_VERSION) > /dev/null) && \
	sleep 10 && \
	echo "\033[32m[OK]\033[0m Localstack is UP. \nUse locally: aws --endpoint-url=http://localhost:4566 [options] <command>" || \
	echo "\033[31m[ERROR]\033[0m Localstack start failed"

CMD_LOCALSTACK_DOWN ?= @ ( $(DOCKER) rm $$($(DOCKER) stop $$($(DOCKER) ps -a -q --filter ancestor=$(LOCALSTACK_IMAGE):$(LOCALSTACK_VERSION) --format="{{.ID}}")) > /dev/null) && echo "\033[32m[OK]\033[0m Localstack is DOWN." || echo "\033[31m[ERROR]\033[0m Localstack stopping failed"

LOCALSTACK_CONTAINER_IP ?= $$($(DOCKER) ps | grep "localstack" > /dev/null && echo "$(LOCALSTACK_IP)" || echo "")
LOCALSTACK_IP ?= $$($(DOCKER) inspect --format='{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' localstack)
AWS_ARGS ?= $$(if [ "$(ENV)" = "localstack" ] && [ $(LOCALSTACK_CONTAINER_IP) ]; then echo "--endpoint-url=http://$(LOCALSTACK_CONTAINER_IP):4566"; else echo ""; fi)

# Tasks
########################################################################################################################
localstack: localstack.up
localstack.up:
	$(CMD_LOCALSTACK_UP)
localstack.down:
	$(CMD_LOCALSTACK_DOWN)