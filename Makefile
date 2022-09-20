KONG_PG_HOST:=host.docker.internal
KONG_PG_DATABASE:=kong
KONG_PG_USER:=kong
KONG_PG_PASSWORD:=password
STORAGE_NAMESPACE:=apiplatform-cp

.PHONY: run-local
run-local:
	@docker build -t audit-logger:dev .
	@docker run -it --rm -e KONG_PG_DATABASE=$(KONG_PG_DATABASE) -e KONG_PG_HOST=$(KONG_PG_HOST) -e KONG_PG_USER=$(KONG_PG_USER) -e KONG_PG_PASSWORD=$(KONG_PG_PASSWORD) -e STORAGE_NAMESPACE=$(STORAGE_NAMESPACE) -v ~/.kube:/mnt/kubectl audit-logger:dev ./program.sh
