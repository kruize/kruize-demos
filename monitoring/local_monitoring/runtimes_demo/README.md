# Kruize Runtimes Recommendations

Kruize provides recommendations for other layers in your application such as the Java Runtime, Quarkus or Spring Boot frameworks along with the resource usage recommendations for the container. You can explore how [runtimes recommendations](https://github.com/kruize/autotune/blob/master/docs/runtimes_recommendations.md) are generated for your Java and Quarkus workloads using this demo.

## Demo workflow

- Deploys Quarkus TechEmpower framework benchmark & Spring PetClinic benchmark from [here](https://github.com/kruize/benchmarks/blob/master/README.md)
- Deploys Kruize instance
- Creates the metric and metadata profiles
- Creates layers with tunables (container, hotspot, openj9 and quarkus layers)
- Creates experiments for these workloads and generates recommendations

## Prerequisites

Ensure you have one of the clusters: Kind, Minikube, or OpenShift.

You also require make and a go version > 1.21. 

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
- Workloads must run for ~30 minutes to collect 2 data points before generating recommendations

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

