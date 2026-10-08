# `make` builds the Hummel-flavoured Slurm test image from the pinned
# slurm-docker submodule.  Needs Docker; the container runs --privileged.
SLURM_VERSION ?= 24.11.7
ROCKY_VERSION ?= 9
IMAGE         ?= hummel-slurm-ci
BASE_IMAGE    ?= slurm-docker-base:$(SLURM_VERSION)-rl$(ROCKY_VERSION)
CONTAINER     ?= hummel-slurm
# e.g. DOCKER_BUILD_FLAGS=--network=host when the default bridge has no working DNS
DOCKER_BUILD_FLAGS ?=

.DEFAULT_GOAL := build
.PHONY: build base up down shell test push clean

slurm-docker/Dockerfile:
	git submodule update --init slurm-docker

base: slurm-docker/Dockerfile  ## upstream image, built from the submodule
	docker build $(DOCKER_BUILD_FLAGS) \
	  --build-arg SLURM_VERSION=$(SLURM_VERSION) \
	  --build-arg ROCKY_VERSION=$(ROCKY_VERSION) \
	  -t $(BASE_IMAGE) slurm-docker

build: base  ## base + Hummel layer
	docker build $(DOCKER_BUILD_FLAGS) \
	  --build-arg BASE_IMAGE=$(BASE_IMAGE) \
	  --build-arg SLURM_VERSION=$(SLURM_VERSION) \
	  -t $(IMAGE):$(SLURM_VERSION) -t $(IMAGE):latest .

up:  ## start the cluster and wait until it is ready
	-docker rm -f $(CONTAINER) >/dev/null 2>&1
	docker run -d --privileged --init --name $(CONTAINER) -h slurmctl $(IMAGE):$(SLURM_VERSION)
	@for i in $$(seq 1 180); do \
	  docker exec $(CONTAINER) test -e /run/hummel-ready 2>/dev/null && { echo "cluster ready"; exit 0; }; \
	  sleep 1; done; \
	echo "cluster did not become ready"; docker logs --tail 50 $(CONTAINER); exit 1

down:
	-docker rm -f $(CONTAINER)

shell:  ## shell as the test user
	docker exec -it -u testuser -w /home/uu/testuser/testuser $(CONTAINER) bash -l

test: up  ## run the self test as the test user
	docker cp tests/selftest.sh $(CONTAINER):/tmp/selftest.sh
	docker exec -u testuser -w /beegfs/uu/testuser/testuser $(CONTAINER) bash /tmp/selftest.sh; rc=$$?; \
	$(MAKE) --no-print-directory down; exit $$rc

push:  ## push versioned and latest tags (log in to the registry first)
	docker push $(IMAGE):$(SLURM_VERSION)
	docker push $(IMAGE):latest

clean: down
	-docker rmi $(IMAGE):$(SLURM_VERSION) $(IMAGE):latest $(BASE_IMAGE)
