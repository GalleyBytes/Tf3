PKG ?= github.com/galleybytes/infra3
DOCKER_REPO ?= ghcr.io/galleybytes
IMAGE_NAME ?= infra3
DEPLOYMENT ?= ${IMAGE_NAME}
NAMESPACE ?= tf-system
VERSION ?= $(shell  git describe --tags --dirty)
ifeq ($(VERSION),)
VERSION := v0.0.0
endif
IMG ?= ${DOCKER_REPO}/${IMAGE_NAME}:${VERSION}
OS := $(shell uname -s | tr A-Z a-z)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: build

# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:crdVersions=v1"

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -xe ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go install sigs.k8s.io/controller-tools/cmd/controller-gen@v0.17.3 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

openapi-gen-bin:
ifeq (, $(shell which openapi-gen))
	@{ \
	set -e ;\
	OPENAPI_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$OPENAPI_GEN_TMP_DIR ;\
	wget -qO kube-openapi.zip https://github.com/kubernetes/kube-openapi/archive/master.zip  ;\
	unzip ./kube-openapi.zip  ;\
	cd kube-openapi-master ;\
	go build -o $(GOBIN)/openapi-gen cmd/openapi-gen/openapi-gen.go ;\
	rm -rf $$OPENAPI_GEN_TMP_DIR ;\
	}
OPENAPI_GEN=$(GOBIN)/openapi-gen
else
OPENAPI_GEN=$(shell which openapi-gen)
endif


client-gen-bin:
ifeq (, $(shell which client-gen))
	@{ \
	set -e ;\
	CLIENT_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CLIENT_GEN_TMP_DIR ;\
	git clone https://github.com/kubernetes/code-generator.git ;\
	cd code-generator ;\
	go install ./cmd/client-gen ;\
	rm -rf $$CLIENT_GEN_TMP_DIR ;\
	}
CLIENT_GEN=$(GOBIN)/client-gen
else
CLIENT_GEN=$(shell which client-gen)
endif


# rbac:roleName=manager-role
# Generate manifests e.g. CRD, RBAC etc.
crds: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) paths="./..." output:crd:stdout > deploy/crds/infra3.galleybytes.com_tfs_crd.yaml

generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

openapi-gen: openapi-gen-bin
	$(OPENAPI_GEN) --logtostderr=true --output-pkg github.com/galleybytes/infra3/pkg/apis/infra3/v1 --output-dir pkg/apis/infra3/v1 --output-file "zz_generated.openapi.go" --go-header-file ./hack/boilerplate.go.txt  -r "-" github.com/galleybytes/infra3/pkg/apis/infra3/v1
 	 
docs:
	/bin/bash hack/docs.sh ${VERSION}

client-gen: client-gen-bin
	$(CLIENT_GEN) -n versioned --input-base ""  --input ${PKG}/pkg/apis/infra3/v1 --output-pkg ${PKG}/pkg/client/clientset --output-dir pkg/client/clientset --go-header-file ./hack/boilerplate.go.txt --plural-exceptions Tf:Tfs

k8s-gen: crds generate openapi-gen client-gen

deploy:
	kubectl delete pod --selector name=${DEPLOYMENT} --namespace ${NAMESPACE} && sleep 4
	kubectl logs -f --selector name=${DEPLOYMENT} --namespace ${NAMESPACE}

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

install: crds
	kubectl apply -f deploy/crds/infra3.galleybytes.com_tfs_crd.yaml

bundle: crds
	/bin/bash hack/bundler.sh ${VERSION}


# Run tests
ENVTEST_ASSETS_DIR=$(shell pwd)/testbin
test: openapi-gen fmt vet crds
	mkdir -p ${ENVTEST_ASSETS_DIR}
	test -f ${ENVTEST_ASSETS_DIR}/setup-envtest.sh || curl -sSLo ${ENVTEST_ASSETS_DIR}/setup-envtest.sh https://raw.githubusercontent.com/kubernetes-sigs/controller-runtime/v0.7.0/hack/setup-envtest.sh
	source ${ENVTEST_ASSETS_DIR}/setup-envtest.sh; fetch_envtest_tools $(ENVTEST_ASSETS_DIR); setup_envtest_env $(ENVTEST_ASSETS_DIR); go test ./... -coverprofile cover.out

build: k8s-gen openapi-gen 




# Development Helpers

# Run against the configured Kubernetes cluster in ~/.kube/config
run: fmt vet
	go run cmd/manager/main.go --max-concurrent-reconciles 10 --zap-log-level=5

install-webhook: fmt vet
	find deploy -maxdepth 1 -type f -name 'webhook-*' -exec kubectl apply -f {} \;



.PHONY: build push run install fmt vet deploy openapi-gen k8s-gen crds contoller-gen client-gen
