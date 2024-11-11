# Local Monitoring with Kruize

Kruize Local provides services to generate recommendations for both single and bulk experiments.

- **For Bulk Services**: For detailed instructions, refer [this guide](https://github.com/kruize/kruize-demos/tree/main/monitoring/local_monitoring/bulk_demo/README.md).
- **For Demo of Individual Experiments**: Continue with the steps below.
- **For Advanced Local Monitoring Options**: Explore advanced testing details [./ReadMe-advancedusers.md].

## Prerequisites
Ensure you have one of the clusters: kind, minikube, or openShift.

**WARNING:** Running the demo script will delete any existing minikube or kind clusters and create a fresh instance.

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
Usage: ./local_monitoring_demo.sh [-s|-t] [-c cluster-type] [-e recommendation_experiment] [-n namespace]
c = supports minikube, kind and openshift cluster-type
e = supports container, namespace, gpu and none. Default - none
s = start (default), t = terminate
n = namespace where demo benchmark is deployed. Default - default
```

## Understanding the Demo

This demo focuses on installing kruize and also installs the demo benchmark
- By default, it installs kruize and provides the URL to access the kruize UI service where the user can create experiments and generate recommendations.
- To use demo benchmarks to create and generate recommendations through a script, pass -e for container, namespace and gpu benchmarks.
    - For container and namespace type, benchmark 'TFB' is deployed in a namespace.
    - For gpu type, benchmark 'human-eval' is deployed.

Here’s a breakdown of what happens during the demo:

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
  - Experiments Created:
        - container: `monitor_tfb_benchmark` and `monitor_tfb-db_benchmark` for the server and database deployments.
        - namespace: `monitor_app_namespace`
        - gpu: `monitor_human_eval_benchmark`
- Generate Recommendations
  - Generates Recommendations for all the experiments created.

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

