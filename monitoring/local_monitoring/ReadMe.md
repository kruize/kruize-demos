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
Usage: ./local_monitoring_demo.sh [-s|-t] [-c cluster-type] [-l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image] [-b] [-n namespace] [-d load-duration] [-m benchmark-manifests]
c = supports minikube, kind and openshift cluster-type
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

## Understanding the Demo

This demo focuses on using the TFB (TechEmpower Framework Benchmarks) benchmark to simulate different load conditions and observe how Kruize-Autotune reacts with its recommendations. Here’s a breakdown of what happens during the demo:

- TFB deployment in default Namespace
    - The TFB benchmark is initially deployed in the default namespace, comprising two key deployments
      - tfb-qrh: Serving as the application server.
      - tfb-database: Database to the server.
    - Load is applied to the server for 20 mins within this namespace to simulate real-world usage scenarios
- Install Kruize
  - Installs kruize under openshift-tuning name.
- Metadata Collection and Experiment Creation
  - Kruize gathers data sources and metadata from the cluster.
  - Experiments `monitor_tfb_benchmark` and `monitor_tfb-db_benchmark` are created for the server and database deployments respectively in the `default` namespace.
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

## Bulk Service Demo

Kruize Local provides a bulk service to generate bulk recommendations based on the bulk service configuration. Refer this [README](https://github.com/kruize/kruize-demos/tree/main/monitoring/local_monitoring/bulk_demo/README.md) to explore bulk service.

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
