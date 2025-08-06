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
Usage: ./local_monitoring_demo.sh [-s|-t] [-c cluster-type] [-f]
c = supports minikube, kind and openshift cluster-type
s = start (default), t = terminate
f = create fresh environment setup if cluster-type is minikube or kind
```

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

