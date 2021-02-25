SHELL = /bin/bash -o pipefail

export PROJECT = tullo-starter-kit
export CLUSTER = tullo-starter-cluster
export VERSION = 1.0
export PAGE = 1
export ROWS = 20

.DEFAULT_GOAL := contexts

contexts:
	@kubectl config get-contexts

use-context:
	@kubectl config use-context kind-$(CLUSTER)

kind-install:
	@GO111MODULE="on" go install -v sigs.k8s.io/kind@v0.10.0

kubeval-install:
	@GO111MODULE=on go install -v github.com/instrumenta/kubeval@0.15.0

kustomize-install:
	@GO111MODULE=on go install -v sigs.k8s.io/kustomize/kustomize/v4@v4.0.1

cluster-create:
	$$(go env GOPATH)/bin/kind create cluster \
		--image kindest/node:v1.20.2 --name $(CLUSTER) --config dev/kind-config.yaml

cluster-delete:
	$$(go env GOPATH)/bin/kind delete cluster --name $(CLUSTER)

cluster-info:
	@kubectl cluster-info --context kind-$(CLUSTER)

images-load:
	@$$(go env GOPATH)/bin/kind load docker-image tullo/sales-api-amd64:$(VERSION) --name $(CLUSTER)
	@$$(go env GOPATH)/bin/kind load docker-image tullo/metrics-amd64:$(VERSION) --name $(CLUSTER)

images-list:
	@docker exec -it $(CLUSTER)-control-plane crictl images

kubeval:
	@$$(go env GOPATH)/bin/kustomize build ./dev | $$(go env GOPATH)/bin/kubeval --strict --force-color -

deployment-apply: kubeval
	@$$(go env GOPATH)/bin/kustomize build ./dev | kubectl apply --validate -f -
#	@$$(go env GOPATH)/bin/kustomize build ./dev | kubectl apply --dry-run=client --validate -f -

deployment-delete:
	@$$(go env GOPATH)/bin/kustomize build ./dev | kubectl delete -f -

update-sales-api:
	@$$(go env GOPATH)/bin/kind load docker-image tullo/sales-api-amd64:$(VERSION) --name $(CLUSTER)
	@$$(go env GOPATH)/bin/kustomize set image deployment -l app=sales-api sales-api=tullo/sales-api-amd64:$(VERSION)

get-pods:
	@kubectl get pods

.PHONY: logs
logs:
	@echo ====== postgres =========================================================
	@kubectl logs --tail=5 -l app=postgres --all-containers=true
	@echo
	@echo ====== metrics ==========================================================
	@kubectl logs --tail=8 -l app=sales-api --container metrics
	@echo
	@echo ====== sales-api ========================================================
	@kubectl logs --tail=5 -l app=sales-api --container app
	@echo
	@echo ====== zipkin ===========================================================
	@kubectl logs --tail=10 -l app=sales-api --container zipkin

schema: get-pods migrate seed

migrate:
	@$(eval APP=`kubectl get pod -l app=sales-api -o jsonpath='{.items[0].metadata.name}'`)
	@kubectl exec -it ${APP} --container app  -- /service/admin --db-disable-tls=1 migrate

seed:
	@$(eval APP=`kubectl get pod -l app=sales-api -o jsonpath='{.items[0].metadata.name}'`)
	@kubectl exec -it ${APP} --container app  -- /service/admin --db-disable-tls=1 seed


health-request:	NODE_IP=$$(docker inspect --format='{{.NetworkSettings.Networks.kind.IPAddress}}' ${CLUSTER}-control-plane)
health-request:
	@echo ====== postgres ======================================================
	@$(eval DB=`kubectl get pod -l "app=postgres" -o jsonpath='{.items[0].metadata.name}'`)
	@kubectl exec -it ${DB} -- pg_isready
	@echo 
	@echo ====== sales-api =====================================================
	@wget -q -O - http://${NODE_IP}:4000/debug/readiness | jq


.PHONY: users-request
users-request: NODE_IP=$$(docker inspect --format='{{.NetworkSettings.Networks.kind.IPAddress}}' ${CLUSTER}-control-plane)
users-request: SIGNING_KEY_ID=54bb2165-71e1-41a6-af3e-7da4a0e1e2c1
users-request: TOKEN_URL=http://${NODE_IP}:3000/v1/users/token/${SIGNING_KEY_ID}
users-request: TOKEN=$$(curl --no-progress-meter --user 'admin@example.com:gophers' ${TOKEN_URL} | jq -r '.token')
users-request: USERS_URL=http://${NODE_IP}:3000/v1/users/${PAGE}/${ROWS}
users-request:
	@wget -q -O - --header "Authorization: Bearer ${TOKEN}" ${USERS_URL} | jq

products-request: NODE_IP=$$(docker inspect --format='{{.NetworkSettings.Networks.kind.IPAddress}}' ${CLUSTER}-control-plane)
products-request: SIGNING_KEY_ID=54bb2165-71e1-41a6-af3e-7da4a0e1e2c1
products-request: TOKEN_URL=http://${NODE_IP}:3000/v1/users/token/${SIGNING_KEY_ID}
products-request: TOKEN=$$(curl --no-progress-meter --user 'admin@example.com:gophers' ${TOKEN_URL} | jq -r '.token')
products-request: PRODUCTS_URL=http://${NODE_IP}:3000/v1/products/${PAGE}/${ROWS}
products-request:
	@wget -q -O - --header "Authorization: Bearer ${TOKEN}" ${PRODUCTS_URL}  | jq

status:
	@echo ====== nodes =========================================================
	@kubectl get nodes
	@echo ====== pods ==========================================================
	@kubectl get pods
	@echo ====== services ======================================================
	@kubectl get services postgres sales-api

sales-api-shell: get-pods
	@$(eval APP=`kubectl get pod -l app=sales-api -o jsonpath='{.items[0].metadata.name}'`)
	@kubectl exec -it ${APP} --container app  -- /bin/sh
