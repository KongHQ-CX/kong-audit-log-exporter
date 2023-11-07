PLATFORM := "linux/amd64"
ARCH := "amd64"
KONG_PG_HOST:=host.docker.internal
KONG_PG_DATABASE:=kong
KONG_PG_USER:=kong
KONG_PG_PASSWORD:=kong
STORAGE_NAMESPACE:=apiplatform-cp

.PHONY: build-image
build-image:
	@docker build -t audit-log-exporter:latest --platform=$(PLATFORM) --build-arg=ARCH=$(ARCH) .

.PHONY: run-local
run-local: build-image
	@docker run -it --rm -e KONG_PG_DATABASE=$(KONG_PG_DATABASE) -e KONG_PG_HOST=$(KONG_PG_HOST) -e KONG_PG_USER=$(KONG_PG_USER) -e KONG_PG_PASSWORD=$(KONG_PG_PASSWORD) -e STORAGE_NAMESPACE=$(STORAGE_NAMESPACE) -v ~/.kube:/mnt/kubectl audit-log-exporter:latest ./program.sh

.PHONY: build-image-jack-stg
build-image-jack-stg:
	@docker build -t registry.stg.jackgpt.co.uk/audit-log-exporter:latest --platform=$(PLATFORM) .
	@docker push registry.stg.jackgpt.co.uk/audit-log-exporter:latest

.PHONY: install-local
install-local: build-image
	@helm upgrade -i audit-log-exporter . -n kong -f values.yaml --set "image.pullPolicy=IfNotPresent" --set "image.repository=audit-log-exporter"
