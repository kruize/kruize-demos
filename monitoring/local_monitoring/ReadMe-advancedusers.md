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
Usage: ./local_monitoring_demo.sh [-s|-t] [-c cluster-type] [-e recommendation_experiment] [-l] [-p] [-f] [-i kruize-image] [-u kruize-ui-image] [-b] [-n namespace] [-d load-duration] [-m benchmark-manifests] [-o kruize-operator-image]
c = supports minikube, kind and openshift cluster-type
e = supports container, namespace and gpu. Default - none.
i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>
l = Run a load against the benchmark
p = expose prometheus port
f = create fresh environment setup if cluster-type is minikube or kind
s = start (default), t = terminate
u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>
b = deploy the benchmark.
n = namespace where benchmark is deployed. Default - default
d = duration to run the benchmark load
m = manifests of the benchmark
o = Deploy Kruize in operator mode with specified operator image. Default - quay.io/kruize/kruize-operator:<version as in Makefile>
k = install kruize using deploy scripts
```

## Operator Mode Deployment

Kruize supports operator mode deployment for all cluster types (kind, minikube, and openshift) using the `-o` flag.

**Deployment Modes**:
- **Operator Mode** (with `-o` flag): Uses the Kruize Operator to deploy and manage Kruize components via Kubernetes Custom Resources (CRDs). The operator handles the lifecycle management of Kruize, including installation, updates, and configuration management.
- **Standard Mode** (default, without `-o` flag): Uses direct deployment manifests to install Kruize components. This is the traditional deployment method where components are deployed directly using kubectl/oc commands.

**Examples**:

For Kind cluster with operator mode:
```sh
./local_monitoring_demo.sh -c kind -f -o quay.io/kruize/kruize-operator:latest
```

For Minikube cluster with operator mode:
```sh
./local_monitoring_demo.sh -c minikube -f -o quay.io/kruize/kruize-operator:latest
```

For OpenShift cluster with operator mode:
```sh
./local_monitoring_demo.sh -c openshift -o quay.io/kruize/kruize-operator:latest
```

For OpenShift with custom experiment type and operator mode:
```sh
./local_monitoring_demo.sh -c openshift -e container -o quay.io/kruize/kruize-operator:latest
```

Refer the documentation of Kruize operator [README.md](https://github.com/kruize/kruize-operator/blob/main/README.md) and [Makefile](https://github.com/kruize/kruize-operator/blob/main/Makefile) for more details.

## Demo Workflow

Here's a breakdown of what happens during the demo:

- Deploys benchmarks in a namespace (if -e is passed)
    - If -e is container/namespace
        - The TFB benchmark is initially deployed in the namespace, comprising two key deployments
          - tfb-qrh: Serving as the application server.
          - tfb-database: Database to the server.
        - Load is applied to the server for 20 mins within this namespace to simulate real-world usage scenarios
    - If -e is gpu
        - The human-eval benchmark is deployed as job in the namespace.
        - The job is set to run for atleast 20 mins to generate the recommendations.
- Install Kruize
  - Installs kruize under openshift-tuning name.
- Metadata Collection and Experiment Creation
  - Kruize gathers data sources and metadata from the cluster.
  - Experiments(-e) Created:
        - none(default): dynamically created based on container and namespace (if no enviroment set-up) ; `monitor_sysbench` ( if environment set-up enabled)  
        - container: `monitor_tfb_benchmark` and `monitor_tfb-db_benchmark` for the server and database deployments.
        - namespace: `monitor_app_namespace`
        - gpu: `monitor_human_eval_benchmark`
- Generate Recommendations
  - Generates Recommendations for all the experiments created.


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
