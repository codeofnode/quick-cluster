#   @file       Makefile
#   @brief      Makefile for different services
#   @author     Ramesh Kumar <codeofnode@gmail.com>

CLUSTER_NAME := myapp
SERVER_APP_NAME := server
CLIENT_APP_NAME := client
COMBINED_APP_NAME := ${CLIENT_APP_NAME}${SERVER_APP_NAME}
TMP_VALUES_YAML := /tmp/myapphelmvalues.yaml
CLUSTER_YAML := cluster.yaml
INSTALL_ARGS := install
SET_VALUES :=

gen:
	rm -f ${TMP_VALUES_YAML} deployments/*
	# this directory shall keep values.yaml file for each helm package
	mkdir -p deployments
	# create values.yaml for each of deployment
	for prefix in $$(yq eval '.cluster | keys' ${CLUSTER_YAML} | awk '{print $$2}'); do \
	    sed \
	      -e s/REPLACE_CLUSTER_NAME/${CLUSTER_NAME}/ \
	      -e s/REPLACE_SERVICE_NAME/$${prefix}/ \
	      -e s/REPLACE_SERVICE_KIND/$$(yq eval '.cluster.'$${prefix}'.kind' ${CLUSTER_YAML})/ \
	      -e s/REPLACE_SERVICE_TYPE/$$(yq eval '.cluster.'$${prefix}'.type' ${CLUSTER_YAML})/ \
	      -e s/REPLACE_DEPLOYMENT_COUNT/$$(yq eval '.cluster.'$${prefix}'.count' ${CLUSTER_YAML})/ \
	      -e s/REPLACE_REPLICA_COUNT/$$(yq eval '.cluster.'$${prefix}'.podCount' ${CLUSTER_YAML})/ \
	        chart/values.yaml > ${TMP_VALUES_YAML}; \
	    cat cluster.yaml >> ${TMP_VALUES_YAML}; \
		cp ${TMP_VALUES_YAML} deployments/$${prefix}.yaml; \
	done

setup:
	! kind get clusters | grep ${CLUSTER_NAME} && \
		kind create cluster --name ${CLUSTER_NAME} || true
	make gen

reset:
	kind get clusters | grep ${CLUSTER_NAME} && \
		kind delete cluster --name ${CLUSTER_NAME} || true
	rm -f ${TMP_VALUES_YAML} deployments/*

# we could generate different tls key pairs for each kind of traffic, but that may be overkill for experiments
# hence using same keypair for each of deployments
# using helm install --dry-run to generate key pair, that is used for all deployments
# we could use openssl but no need for another dependency
run:
	make gen
	set -e; \
	for fl in ./deployments/*.yaml; do \
      BS_NAME=$$(basename $$fl | cut -d '.' -f1); \
      CL_NAME=${CLUSTER_NAME}-$${BS_NAME}; \
      SVC_TYPE=$$(yq eval '.cluster.'$${BS_NAME}'.type' $${fl}); \
	  helm ${INSTALL_ARGS} $${CL_NAME} ./chart -f $${fl} ${SET_VALUES} & \
	done; \
    wait

clean:
	set -e; \
	for fl in ./deployments/*.yaml; do \
	  CL_NAME=${CLUSTER_NAME}-$$(basename $$fl | cut -d '.' -f1); \
	  helm get manifest $${CL_NAME} >/dev/null && \
         helm uninstall $${CL_NAME} & \
	done; \
    wait

dry-run:
	make run INSTALL_ARGS="install --debug --dry-run"

template:
	make run INSTALL_ARGS="template --debug"

exec:
	kubectl exec -it deployment/${DEP_NAME}-1 -- sh

desc:
	kubectl describe deployment/${DEP_NAME}-1

debug:
	make run SET_VALUES="--set debugMode=true"
	sleep 5
	make exec

logs:
	kubectl logs deployment/${DEP_NAME}-1 -f
