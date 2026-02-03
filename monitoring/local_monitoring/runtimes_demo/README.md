# Kruize Runtimes Recommendations

Kruize provides recommendations for other layers in your application such as the Java Runtime, Quarkus or Springboot frameworks along with the resource usage recommendations for the container. You can explore how runtimes recommendations are generated for your Java and Quarkus workloads using this demo.

## Demo workflow

- Deploys a Quarkus Hotspot JVM workload and a Springboot OpenJ9 JVM workload
- Deploys Kruize instance
- Creates the metric and metadata profiles
- Creates layers with tunables (container, hotspot, openj9 and quarkus layers)
- Creates experiments for these workloads and generates recommendations

## Prerequisites
Ensure you have one of the clusters: kind, minikube, or openShift.

You also require make and a go version > 1.21. 

On Openshift cluster, enable user workload monitoring to monitoring user defined workloads by following the below steps:

Edit the `cluster-monitoring-config` ConfigMap if present and add/update enableUserWorkload to true:

```
oc -n openshift-monitoring edit configmap cluster-monitoring-config
```

Add or update:
```
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```
Save and exit.
If cluster-monitoring-config is not present, create the config map by saving the above in a yaml and applying it.

Monitoring for user workloads will be enabled automatically. Verify
```
oc -n openshift-user-workload-monitoring get pods
```
Ensure the following pods are running:
```
prometheus-operator
prometheus-user-workload
thanos-ruler-user-workload
```
Note: It may take a few minutes for these pods to start.


## Getting Started with the Demo

To begin exploring the Kruize Runtimes recommendations, follow these steps:

### Run the Demo

##### Clone the demo repository:
```sh
git clone git@github.com:kruize/kruize-demos.git
```
##### Change directory to the runtimes demo:
```sh
cd kruize-demos/monitoring/local_monitoring/runtimes_demo
```
***Note***: We support `Kind`, `Minikube` and `OpenShift` clusters. By default, it runs on the `Kind` cluster.

### For Kind / Minikube Clusters

#### Option 1: Fresh Setup with `-f` flag (Recommended)
```sh
./runtimes_demo.sh -c kind -f
```
Automatically installs a clean Kind/Minikube cluster, Prometheus, and monitoring namespace.

#### Option 2: Existing Setup without `-f` flag
```sh
./runtimes_demo.sh
```
**Prerequisites**:
- Kind/Minikube cluster running
- Prometheus installed
- Monitoring namespace created
- Workloads must run for ~30 minutes to collect 2 datapoints before generating recommendations

### For OpenShift Cluster

```sh
./runtimes_demo.sh -c openshift
```
**Note**: The `-f` flag is not supported for OpenShift as Prometheus is already pre-installed.

### Deployment Modes

**Operator Mode (Default)**: Kruize is deployed using the Kruize Operator, which manages Kruize components via Kubernetes Custom Resources (CRDs). This is the recommended deployment method.

**Quick Examples**:
```sh
# Default operator deployment (uses default operator image)
./runtimes_demo.sh -c kind -f

# Specify custom operator image
./runtimes_demo.sh -c kind -f -o quay.io/kruize/kruize-operator:latest

# Use deploy scripts instead of operator
./runtimes_demo.sh -c kind -f -k
```

### Usage

```
./runtimes_demo.sh [-s|-t] [-c cluster-type] [-f] [-i kruize-image] [-o kruize operator image] [-k]
s = start demo (default)
t = terminate demo
c = supports minikube, kind and openshift cluster-type
f = create environment setup if cluster-type is minikube, kind
i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>
o = Kruize operator image. Default - quay.io/kruize/kruize-operator:<version as in Makefile>
k = Disable operator and install kruize using deploy scripts instead.
```

Refer to the Kruize operator documentation [README.md](https://github.com/kruize/kruize-operator/blob/main/README.md) and [Makefile](https://github.com/kruize/kruize-operator/blob/main/Makefile) for more details.

