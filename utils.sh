create_dirs() {
  mkdir -p $DIR/sandbox/bin
  mkdir -p $DIR/sandbox/configs
  export PATH=$DIR/sandbox/bin:$PATH
  cp -r $DIR/certs $DIR/infra $DIR/apigw $DIR/svc $DIR/sandbox/
  echo "$1" > $DIR/sandbox/clusterkind
  cd $DIR/sandbox
}

get_namespaces() {
  echo $($DIR/sandbox/bin/yq r $DIR/values.yaml 'namespaces[*].name' | cut -d ' ' -f2)
}

get_services() {
  echo $($DIR/sandbox/bin/yq r $DIR/values.yaml "namespaces[$1].services[*].name" | cut -d ' ' -f2)
}

get_cluster() {
  cluster=$($DIR/sandbox/bin/yq r $DIR/values.yaml cluster)
  if [ "$cluster" == "null" ]; then cluster=$($DIR/sandbox/bin/yq r $DIR/values.yaml namespaces[0].name); fi
  echo $cluster
}

patch_isito_gateway() {
  cluster=$(get_cluster)
  $DIR/sandbox/bin/yq w -i -d0 apigw/istio.yaml metadata.name $cluster-gateway
  $DIR/sandbox/bin/yq w -i -d* apigw/istio.yaml metadata.namespace $cluster
  $DIR/sandbox/bin/yq w -i -d2 apigw/istio.yaml metadata.name $cluster
  $DIR/sandbox/bin/yq w -i -d2 apigw/istio.yaml "spec.gateways[0]" $cluster-gateway
}

download_tools() {
  if [ ! -f ./bin/kind > /dev/null 2>&1 ]; then
    curl -Lo ./bin/kind https://github.com/kubernetes-sigs/kind/releases/download/v0.6.0/kind-$(uname)-amd64
    chmod +x ./bin/kind
  fi
  if [ ! -f ./bin/yq > /dev/null 2>&1 ]; then
    curl -Lo ./bin/yq https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_amd64
    chmod +x ./bin/yq
  fi
  if [ ! -f ./bin/helm > /dev/null 2>&1 ]; then
    wget https://get.helm.sh/helm-v3.0.2-linux-amd64.tar.gz
    tar -zxf helm-v3.0.2-linux-amd64.tar.gz
    mv linux-amd64/helm ./bin/helm
    chmod +x ./bin/helm
  fi
  if [ ! -f ./bin/istioctl > /dev/null 2>&1 ]; then
    curl -L https://istio.io/downloadIstio | sh -
    ln -s ../istio-1.4.2/bin/istioctl bin/istioctl
  fi
}

setup_svcs() {
  if [ ! -d mockserver > /dev/null 2>&1 ]; then
    git clone https://github.com/mock-server/mockserver.git
    cd mockserver
    git checkout tags/mockserver-5.8.0
    sed -i 's|{{ .Values.image.repository }}/mockserver:mockserver-{{- if .Values.image.snapshot }}snapshot{{- else }}{{ .Chart.Version }}{{- end }}|williamyeh/json-server:1.1.1|' helm/mockserver/templates/deployment.yaml
    sed -i 's|imagePullPolicy: Always|command: ["json-server", "/config/db.json", "--host", "0.0.0.0", "--routes", "/config/routes.json"]|' helm/mockserver/templates/deployment.yaml
    sed -i 's|mockserver.properties|db.json|' helm/mockserver-config/templates/configmap.yaml
    sed -i 's|initializerJson.json|routes.json|' helm/mockserver-config/templates/configmap.yaml
    sed -i 's|serviceport|http|' helm/mockserver/templates/service.yaml
    sed -i 's|serviceport|http|' helm/mockserver/templates/ingress.yaml
    sed -i 's|serviceport|http|' helm/mockserver/templates/deployment.yaml
    cd ..
  fi
  cd mockserver
  sed -i 's|mockserver.properties|db.json|' helm/mockserver-config/templates/configmap.yaml
  sed -i 's|initializerJson.json|routes.json|' helm/mockserver-config/templates/configmap.yaml
  nc=0
  cluster_type=`cat $DIR/sandbox/clusterkind`
  if [ "$cluster_type" == "istio" ]; then
    routeRule=$($DIR/sandbox/bin/yq r -d2 ../apigw/istio.yaml spec.http | sed -e 's/^/  /')
  fi
  for ns in $(get_namespaces); do 
    ss=0
    for sc in $(get_services $nc); do 
      if [ "$cluster_type" == "istio" ]; then
        if [ "$ss" == "0" ]; then
          sed -i "s/svc/$sc/" ../apigw/istio.yaml
        fi
      fi
      i=$ns-$sc
      rm -rf helm/$i-config
      cp -r helm/mockserver-config helm/$i-config
      sed -i 's/name: mockserver-config/name: '$i'-configmap/' helm/$i-config/Chart.yaml
      cp -r $DIR/svc/mock/* helm/$i-config/static/
      cp -r $DIR/svc/mock/* helm/$i-config/static/
      cp $DIR/svc/values.yaml helm/$i-config/
      if [ "$cluster_type" == "istio" ]; then
        if [ "$ss" != "0" ]; then
          echo "$routeRule" | sed -e "s/svc/$sc/" >> ../apigw/istio.yaml
        fi
      fi
      $DIR/sandbox/bin/yq w -i helm/$i-config/values.yaml nameOverride $sc
      $DIR/sandbox/bin/yq w -i helm/$i-config/values.yaml app.mountedConfigMapName $i-configmap
      if [ "$cluster_type" == "istio" ]; then
        $DIR/sandbox/bin/yq w -i helm/$i-config/values.yaml ingress.enabled "false"
      else
        $DIR/sandbox/bin/yq w -i helm/$i-config/values.yaml ingress.path /$sc
      fi
      $DIR/sandbox/bin/yq m -i helm/$i-config/values.yaml $DIR/values.yaml
      ss=$[$ss +1]
    done
    nc=$[$nc +1]
  done
  cd ..
}
