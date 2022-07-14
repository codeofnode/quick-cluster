# quick-cluster
A quick k8s cluster made with different services talking to each other, with different protocols like http, https and http2

# requirements
docker v20.10+
kubectl v1.24.0+
kind ~v0.14+
helm ~v3.9+
yq ~v4.25+

# cluster.yaml
This file defines how the cluster look like and what is expected traffic to be flown between services
```
cluster:
  <deployment-name-1>:
    kind: server  # client or server or clientserver (acting as both serving request and making request)
    type: http  # http or http2 or https
    count: 2 # how many deployments/services to be created. all services will be named <deployment-name-1>-{1,2,3...}
    podCount: 2 # how many pods to be created with each deployment
  <deployment-name-2>:
    ...
traffics:
  - type: http  # http or https or http2, what kind of network traffic to be generated
    randomSleepDigits: 0  # sleep before first request, and all subsequent requests, just to make real world kind of scenario, 
      a random number of specific digits, set 0 for no sleep
    from:
      - <one of deployment names which has type == client or clientserver>  # client or clientserver
      - <from bucket of selected deployment which service to hit>  # index of client or clientserver, base 1
    to:
      - <one of deployment names which has type == server or clientserver>  # client or clientserver
      - <from bucket of selected deployment which service to hit>  # index of server or clientserver, base 1
```

# getting started after having requirements fulfilled
```
make setup
#make dry-run # to see what config is being generated
make run
```

# cleanup the helm
```
make clean
```

# cleanup everything
```
make reset
```

# debugging
```
# helm install and exec into pod to do all sort of cool stuffs
# make debug DEP_NAME=<one_of_deployment_names_defined_in_cluster.yaml_as_cluster.<deployment-name-1>>
make debug DEP_NAME=client

# don't install, just exec into already installed deployment
# make exec DEP_NAME=<one_of_deployment_names_defined_in_cluster.yaml_as_cluster.<deployment-name-1>>
make exec DEP_NAME=client

# see logs of already installed deployment
# make logs DEP_NAME=<one_of_deployment_names_defined_in_cluster.yaml_as_cluster.<deployment-name-1>>
make logs DEP_NAME=client
```
