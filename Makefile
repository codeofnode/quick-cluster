#   @file       Makefile
#   @brief      Makefile for different services
#   @author     Ramesh Kumar <codeofnode@gmail.com>

CLUSTER_NAME := myapp
SERVER_APP_NAME := server
CLIENT_APP_NAME := client
COMBINED_APP_NAME := ${CLIENT_APP_NAME}${SERVER_APP_NAME}
TMP_FILE := /tmp/${CLIENT_APP_NAME}clustertempfile
TMP_CA_FILES := /tmp/${CLUSTER_NAME}-ca-certs
CLUSTER_YAML := cluster.yaml
INSTALL_ARGS := install
SET_VALUES :=

gen:
	rm -rf ${TMP_FILE} ${TMP_CA_FILES} deployments/*
	# this directory shall keep values.yaml file for each helm package
	mkdir -p deployments ${TMP_CA_FILES}
	openssl genrsa -out ${TMP_CA_FILES}/ca.key 2048
	openssl req -x509 -new -nodes -key ${TMP_CA_FILES}/ca.key -sha256 -days 1825 -out ${TMP_CA_FILES}/ca.crt \
		-subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=example.com"
	# create values.yaml for each of deployment
	for prefix in $$(yq eval '.cluster | keys' ${CLUSTER_YAML} | awk '{print $$2}'); do \
	    sed \
	      -e s/REPLACE_CLUSTER_NAME/${CLUSTER_NAME}/ \
	      -e s/REPLACE_SERVICE_NAME/$${prefix}/ \
	      -e s/REPLACE_BASE64_CA_KEY/$$(cat ${TMP_CA_FILES}/ca.key | base64 -w0)/ \
	      -e s/REPLACE_BASE64_CA_CERT/$$(cat ${TMP_CA_FILES}/ca.crt | base64 -w0)/ \
	      -e s/REPLACE_SERVICE_KIND/$$(yq eval '.cluster.'$${prefix}'.kind' ${CLUSTER_YAML})/ \
	      -e s/REPLACE_SERVICE_TYPE/$$(yq eval '.cluster.'$${prefix}'.type' ${CLUSTER_YAML})/ \
	      -e s/REPLACE_DEPLOYMENT_COUNT/$$(yq eval '.cluster.'$${prefix}'.count' ${CLUSTER_YAML})/ \
	      -e s/REPLACE_REPLICA_COUNT/$$(yq eval '.cluster.'$${prefix}'.podCount' ${CLUSTER_YAML})/ \
	        chart/values.yaml > ${TMP_FILE}; \
	    cat cluster.yaml >> ${TMP_FILE}; \
		cp ${TMP_FILE} deployments/$${prefix}.yaml; \
	done

setup:
	! kind get clusters | grep ${CLUSTER_NAME} && \
		kind create cluster --name ${CLUSTER_NAME} || true
	make gen

reset:
	kind get clusters | grep ${CLUSTER_NAME} && \
		kind delete cluster --name ${CLUSTER_NAME} || true
	rm -f ${TMP_FILE} deployments/*

helm_run:
	set -e; \
	for fl in ./deployments/*.yaml; do \
      BS_NAME=$$(basename $$fl | cut -d '.' -f1); \
      CL_NAME=${CLUSTER_NAME}-$${BS_NAME}; \
      SVC_TYPE=$$(yq eval '.cluster.'$${BS_NAME}'.type' $${fl}); \
	  helm ${INSTALL_ARGS} $${CL_NAME} ./chart -f $${fl} ${SET_VALUES} & \
	done; \
    wait

run:
	make gen
	kubectl create secret generic ${CLUSTER_NAME}-ca-cert --from-file=ca.crt=${TMP_CA_FILES}/ca.crt
	make helm_run

clean:
	set -e; \
	for fl in ./deployments/*.yaml; do \
	  CL_NAME=${CLUSTER_NAME}-$$(basename $$fl | cut -d '.' -f1); \
	  helm get manifest $${CL_NAME} >/dev/null && \
         helm uninstall $${CL_NAME} & \
	done; \
    wait
	kubectl delete secret ${CLUSTER_NAME}-ca-cert

dry-run:
	make helm_run INSTALL_ARGS="install --debug --dry-run"

template:
	make helm_run INSTALL_ARGS="template --debug"

exec:
	kubectl exec -it deployment/${DEP}-1 -- sh

desc:
	kubectl describe deployment/${DEP}-1

debug:
	make helm_run SET_VALUES="--set debugMode=true"
	sleep 5
	make exec

logs:
	kubectl logs deployment/${DEP}-1 --tail 10 -f
