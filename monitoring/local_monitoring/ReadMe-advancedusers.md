# Local Monitoring with Kruize - Advanced User Guide

## Getting Started

To begin exploring local monitoring capabilities, follow these steps:

##### Clone the demo repository:
```sh
git clone git@github.com:kruize/kruize-demos.git
```
##### Change directory to the local monitoring demo:
```sh
cd kruize-demos/monitoring/local_monitoring
```
***Note*** : We support `Kind`, `Minikube` and `Openshift` clusters.
By default, it runs on the `Kind` cluster.
##### Execute the demo script on kind as: 
```sh
./local_monitoring_demo.sh
```
##### Execute the demo script in openshift as: 
```sh
./local_monitoring_demo.sh -c openshift
```

```
Usage: ./local_monitoring_demo.sh [-s|-t] [-c cluster-type] [-e recommendation_experiment] [-l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image] [-b] [-n namespace] [-d load-duration] [-m benchmark-manifests]
c = supports minikube, kind and openshift cluster-type
e = supports container, namespace and gpu. Default - none.
i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>
l = Run a load against the benchmark
p = expose prometheus port
r = restart kruize only
s = start (default), t = terminate
u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>
b = deploy the benchmark.
n = namespace where benchmark is deployed. Default - default
d = duration to run the benchmark load
m = manifests of the benchmark
```

## Misc

##### To apply the load to TFB benchmark: 
```sh
./local_monitoring_demo.sh -c openshift -l -n <APP_NAMESPACE> -d <LOAD_DURATION>
./local_monitoring_demo.sh -c openshift -l -n "default" -d "1200"
```

#### To refresh datasource metadata

To refresh the datasource metadata,
- Delete the previosuly imported metadata
- Import the metdata from the datasource

Commands to refresh metadata

```sh
# Replace KRUIZE_URL with the URL to connect to Kruize

# Delete previously imported metadata
curl -X DELETE http://"${KRUIZE_URL}"/dsmetadata \
--header 'Content-Type: application/json' \
--data '{
     "version": "v1.0",
     "datasource_name": "prometheus-1"
}'

# Import metadata from prometheus-1 datasource                   
curl --location http://"${KRUIZE_URL}"/dsmetadata \
--header 'Content-Type: application/json' \
--data '{
     "version": "v1.0",
     "datasource_name": "prometheus-1"
}'

# Display metadata from prometheus-1 datasource
curl "http://${KRUIZE_URL}/dsmetadata?datasource=prometheus-1&verbose=true"

# Display metadata for a "prometheus-1" datasource in "default" namespace and "default" cluster
curl "http://${KRUIZE_URL}/dsmetadata?datasource=prometheus-1&cluster_name=default&namespace=default&verbose=true"
``` 
