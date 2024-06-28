# Local Monitoring with Kruize

With Kruize's local monitoring mode, let's explore a demonstration of local monitoring, highlighting how it provides customized recommendations for various load scenarios in Openshift.

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
##### Execute the demo script in openshift as: 
```sh
./local_monitoring_demo.sh -c openshift
```

## Understanding the Demo

This demo focuses on using the TFB (TechEmpower Framework Benchmarks) benchmark to simulate different load conditions and observe how Kruize-Autotune reacts with its recommendations. Here’s a breakdown of what happens during the demo:

- TFB deployment in default Namespace
    - The TFB benchmark is initially deployed in the default namespace, comprising two key deployments
      - tfb-qrh: Serving as the application server.
      - tfb-database: Database to the server.
- Install Kruize
  - Installs kruize under openshift-tuning name.
- Metadata Collection and Experiment Creation
  - Kruize gathers data sources and metadata from the cluster.
  - Experiments `monitor_tfb_benchmark` and `monitor_tfb-db_benchmark` are created for the server and database deployments respectively in the `default` namespace.
- Creating a New Namespace and Application deployment
  - A new namespace named test-multiple-import is created.
  - The TFB benchmark is deployed in the test-multiple-import namespace.
  - Load is applied to the server for 20 mins within this namespace to simulate real-world usage scenarios.
- Metadata Refresh and Experiment Setup
  - Kruize updates its metadata to include the test-multiple-import namespace.
  - New experiments `monitor_tfb_benchmark_multiple_import` and `monitor_tfb-db_benchmark_multiple_import` are created for the server and database deployments in `test-multiple-import` namespace.
- Generate Recommendations
  - Generates Recommendations for all the experiments created.

## Recommendations for different load Simulations observed on Openshift
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

## Misc

##### To apply the load to TFB benchmark: 
```sh
./local_monitoring_demo.sh -c openshift -l -n <APP_NAMESPACE> -d <LOAD_DURATION>
./local_monitoring_demo.sh -c openshift -l -n "test-multiple-import" -d "1200"
```
  
