# Local Monitoring with Kruize

Kruize Local provides services to generate recommendations for both single and bulk experiments.

- **For Bulk Services**: For detailed instructions, refer [this guide](https://github.com/kruize/kruize-demos/tree/main/monitoring/local_monitoring/bulk_demo/README.md).
- **For Demo of Individual Experiments**: Continue with the steps below.
- **For Advanced Local Monitoring Options**: Explore advanced testing details [here](./ReadMe-advancedusers.md)

## Prerequisites
Ensure you have one of the clusters: kind, minikube, or openShift.

You also require make and a go version > 1.21. 

## Getting Started with the Demo

To begin exploring local monitoring capabilities, follow these steps:

### Run the Demo

##### Clone the demo repository:
```sh
git clone git@github.com:kruize/kruize-demos.git
```
##### Change directory to the local monitoring demo:
```sh
cd kruize-demos/monitoring/local_monitoring
```
***Note***: We support `Kind`, `Minikube` and `OpenShift` clusters. By default, it runs on the `Kind` cluster.

### For Kind / Minikube Clusters

#### Option 1: Fresh Setup with `-f` flag (Recommended)
```sh
./local_monitoring_demo.sh -c kind -f
```
Automatically installs a clean Kind/Minikube cluster, Prometheus, and monitoring namespace.

#### Option 2: Existing Setup without `-f` flag
```sh
./local_monitoring_demo.sh
```
**Prerequisites**:
- Kind/Minikube cluster running
- Prometheus installed
- Monitoring namespace created
- Workloads must run for ~30 minutes to collect 2 datapoints before generating recommendations

### For OpenShift Cluster

```sh
./local_monitoring_demo.sh -c openshift
```
**Note**: The `-f` flag is not supported for OpenShift as Prometheus is already pre-installed.

### Operator Mode Deployment

Kruize can be deployed in operator mode for all cluster types (kind, minikube, and openshift) using the `-o` flag.

**Quick Example**:
```sh
./local_monitoring_demo.sh -c kind -f -o quay.io/kruize/kruize-operator:latest
```

**Deployment Modes**:
- **Operator Mode** (with `-o` flag): Uses the Kruize Operator to deploy and manage Kruize components via Kubernetes Custom Resources (CRDs). The operator handles the lifecycle management of Kruize.
- **Standard Mode** (default, without `-o` flag): Uses direct deployment manifests to install Kruize components. This is the traditional deployment method.

**Note**: If no operator image is specified with the `-o` flag, it uses the latest version `quay.io/kruize/kruize-operator:<version>`.

For more examples and advanced operator mode usage, see the [Advanced Users Guide](./ReadMe-advancedusers.md#operator-mode-deployment).

### Usage
```
./local_monitoring_demo.sh [-s|-t] [-c cluster-type] [-f] [-o kruize-operator-image]
  -c: Cluster type (kind, minikube, openshift)
  -s: Start demo (default)
  -t: Terminate demo
  -f: Fresh setup (kind/minikube only)
  -o: Deploy Kruize in operator mode with specified operator image
```

Refer the documentation of Kruize operator [README.md](https://github.com/kruize/kruize-operator/blob/main/README.md) and [Makefile](https://github.com/kruize/kruize-operator/blob/main/Makefile) for more details.

## Understanding the Demo

This demo covers the steps to install Kruize, create an experiment, and generate recommendations.
- By default, it creates an experiment for a container which is long running in a cluster and generates recommendations for the same.
- If user creates an environment set-up for minikube/kind, benchmark 'sysbench' is installed and that container is used to create experiment and generate recommendations.

## Using kruize UI

Refer [this](https://www.loom.com/share/d7ace86fddad43918f777835f70b743f?sid=2470c59e-e160-4dff-b664-83a925d6958c) video on how to create experiments and generate recommendations!

## Recommendations for different load Simulations observed on Openshift

TFB (TechEmpower Framework Benchmarks) benchmark is simulated in different load conditions and below are the different recommendations observed from Kruize-Autotune.

### IDLE 
- Experiment: `monitor_tfb-db_benchmark`
  - Shows an IDLE scenario where CPU recommendations are not generated due to minimal CPU usage (less than a millicore).
  ![idle](https://github.com/kusumachalasani/autotune-demo/assets/17760990/9e1505ca-6c75-4da7-a154-3c6ed3adf3ed)
### Over Provision
- Experiment: `monitor_tfb_benchmark_multiple_import`
  - Highlights over-provisioning where CPU recommendations are lower than the current CPU requests. This scenario also demonstrates over-provisioning in memory usage.
  ![overprovision](https://github.com/kusumachalasani/autotune-demo/assets/17760990/9aac1d35-0e4b-44c6-b358-5eaf00c2852d)
### Under Provision
- Experiment: `monitor_tfb-db_benchmark_multiple_import`
  - Illustrates under-provisioning where CPU recommendations exceed the current CPU requests, suggesting adjustments for improved efficiency.
  ![underprovision](https://github.com/kusumachalasani/autotune-demo/assets/17760990/9005a59d-db4c-41b4-b170-90adf0fafff0)

