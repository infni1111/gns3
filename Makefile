IMAGE ?= gns3:latest
NAME  ?= gns3-server

.PHONY: build run stop restart logs shell ps clean rebuild

build:
	docker build -t $(IMAGE) .

run:
	docker run -d --name $(NAME) \
	  --restart unless-stopped \
	  --privileged \
	  --cap-add NET_ADMIN --cap-add NET_RAW \
	  -p 3080:3080 -p 8080:8080 \
	  --device /dev/net/tun \
	  $(if $(wildcard /dev/kvm),--device /dev/kvm,) \
	  -v gns3-data:/data \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  $(IMAGE)

stop:
	-docker stop $(NAME)
	-docker rm   $(NAME)

restart: stop run

logs:
	docker logs -f $(NAME)

shell:
	docker exec -it $(NAME) bash

ps:
	docker ps -a --filter name=$(NAME)

clean: stop
	-docker volume rm gns3-data

rebuild: clean
	docker build --no-cache -t $(IMAGE) .
	$(MAKE) run
