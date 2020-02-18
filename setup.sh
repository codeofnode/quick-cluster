set -e
PRV_DIR=$(pwd)
DIR="$(cd `dirname $0` && pwd)"

source $DIR/utils.sh
cluster=$(get_cluster)
cluster_type=${1:-istio}

pre_setup() {
  create_dirs $cluster_type
  if [ "$cluster_type" == "istio" ]; then
    patch_isito_gateway
  fi
  download_tools
  setup_svcs
}

export_kubectl() {
  if command -v kctl > /dev/null 2>&1; then
    kctl ln local $DIR/sandbox/configs/$cluster
    source kctl
  else
    export KUBECONFIG=$DIR/sandbox/configs/$cluster
  fi
}

cluster_setup() {
  rm -f $DIR/sandbox/configs/$cluster
  if ! $DIR/sandbox/bin/kind get clusters | grep $cluster; then
    $DIR/sandbox/bin/kind create cluster --name $cluster --kubeconfig $DIR/sandbox/configs/$cluster
  fi
  export_kubectl
  kubectl create ns apigw
  kubectl create ns infra
  for ns in $(get_namespaces); do
    kubectl create ns $ns
    if [ "$cluster_type" == "istio" ]; then
      kubectl label namespace $ns istio-injection=enabled
    elif [ "$cluster_type" == "kuma" ]; then
      kubectl label namespace $ns kuma.io/sidecar-injection=enabled
    fi
  done
}

apigw_setup() {
  export IP=$(ip -o -4 a | tail -1 | awk '{print $4 }' | sed -e 's/\/.*$//')
  if [ "$IP" == "" ]; then IP=172.17.0.1; fi
  helm install apigw stable/kong --namespace apigw -f apigw/values.yaml --set proxy.externalIPs[0]=$IP
}
 
konginfra_setup() {
  helm install prometheus stable/prometheus --namespace infra -f infra/prometheus/values.yaml
  helm install grafana stable/grafana --namespace infra --values http://bit.ly/2FuFVfV
}

kong_plugins_setup() {
  for ns in $(get_namespaces); do 
    yq w -d'*' apigw/kong.yaml metadata.namespace $ns | kubectl apply -f -
  done
}

istio_plugins_setup() {
  kubectl create -n istio-system secret tls istio-ingressgateway-certs --key ./certs/server.key --cert ./certs/server.cert
  kubectl apply -f ./apigw/istio.yaml
}

kong_setup() {
  konginfra_setup
  apigw_setup
  kong_plugins_setup
}

kuma_setup() {
  $DIR/sandbox/bin/kumactl install control-plane | kubectl apply -f -
  #kuma_yaml
  #$DIR/sandbox/bin/kind load docker-image kuma/kuma-cp:$KUMA_CP_TAG --name $cluster
  #kubectl apply -f $DIR/sandbox/kumamesh.yaml
}

istio_setup() {
  $DIR/sandbox/bin/istioctl manifest apply --set profile=demo
  istio_plugins_setup
}

wait_for_pod() {
  echo "waiting for pod ..."
  while [[ $(kubectl get pods -n $1 $2 -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
  done
}

istio_port_forwards() {
  killall kubectl || true
  sleep 20
  POD_NAME=$(kubectl -n istio-system get pod -l istio=sidecar-injector -o jsonpath='{.items[0].metadata.name}')
  wait_for_pod istio-system $POD_NAME
  POD_NAME=$(kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}')
  wait_for_pod istio-system $POD_NAME
  kubectl -n istio-system port-forward $POD_NAME 3000 &
}

kuma_port_forwards() {
  killall kubectl || true
  sleep 20
  POD_NAME=$(kubectl get pods -n kuma-system -l "app=kuma-injector" -o jsonpath="{.items[0].metadata.name}")
  wait_for_pod kuma-system $POD_NAME
}

kong_port_forwards() {
  killall kubectl || true
  sleep 3
  POD_NAME=$(kubectl get pods -n infra -l "app=prometheus,component=server" -o jsonpath="{.items[0].metadata.name}")
  wait_for_pod infra $POD_NAME
  kubectl -n infra port-forward $POD_NAME 9090 &
  POD_NAME=$(kubectl get pods --namespace infra -l "app=grafana" -o jsonpath="{.items[0].metadata.name}")
  wait_for_pod infra $POD_NAME
  kubectl -n infra port-forward $POD_NAME 3000 &
  POD_NAME=$(kubectl get pods --namespace apigw -l "app=kong" -o jsonpath="{.items[0].metadata.name}")
  wait_for_pod apigw $POD_NAME
  kubectl -n apigw port-forward $POD_NAME 8000 &
}

svc_setup() {
  nc=0
  for ns in $(get_namespaces); do 
    for sc in $(get_services $nc); do 
      if [ "$sc" == "policy" ]; then
        $DIR/sandbox/bin/helm install $sc ./mockserver/helm/mockserver --namespace $ns -f ./mockserver/helm/$ns-$sc-config/values.yaml
        $DIR/sandbox/bin/helm install $ns-$sc-config ./mockserver/helm/$ns-$sc-config --namespace $ns
      else
        echo pushd $DIR/sandbox \> /dev/null\; $DIR/sandbox/bin/helm install $sc ./mockserver/helm/mockserver --namespace $ns -f ./mockserver/helm/$ns-$sc-config/values.yaml\; $DIR/sandbox/bin/helm install $ns-$sc-config ./mockserver/helm/$ns-$sc-config --namespace $ns\; popd
      fi
    done
    nc=$[$nc +1]
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  pre_setup
  cluster_setup
  if [ "${CLUSTER_CUSTOM_INSTALL_SETUP}" != "" ]; then
    KIND_BIN=$DIR/sandbox/bin/kind CLUSTER_NAME=$cluster bash ${CLUSTER_CUSTOM_INSTALL_SETUP}
  else
    ${cluster_type}_setup
    ${cluster_type}_port_forwards
  fi
  svc_setup
fi

cd $PRV_DIR
