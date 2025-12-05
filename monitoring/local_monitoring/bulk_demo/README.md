# Bulk recommendations with Kruize Local

With Kruize's local monitoring mode, let's explore a demonstration of generating bulk recommendations using the Bulk API. 

Bulk API is designed to provide resource optimization recommendations in bulk for all available
containers, namespaces, etc., for a cluster connected via the datasource integration framework. Bulk can
be configured using filters like exclude/include namespaces, workloads, containers, or labels for generating
recommendations. It also has settings to generate recommendations at both the container or namespace level, or both.

Bulk returns a `job_id` as a response to track the job status. The user can use the `job_id` to monitor the
progress of the job. User can invoke listRecommendations API for the processed experiments to fetch the recommendations from Kruize. 

Refer the documentation of the [Bulk API](https://github.com/kruize/autotune/blob/master/design/BulkAPI.md) for details.

## Demo workflow

- Deploys Kruize and creates the metric profile
- Invokes the Bulk API using the configuration in bulk_input.json
- Obtains the bulk job status using the job_id returned from the Bulk API
- Waits until the job status is COMPLETED and fetches the recommendations for all the processed experiments
- Stores the bulk job status in job_status.json and all the recommendations in recommendations_data.json

To begin exploring the bulk API capabilities, follow these steps:

### Run the Demo

##### Clone the demo repository:
```sh
git clone git@github.com:kruize/kruize-demos.git
```
##### Change directory to the local monitoring demo:
```sh
cd kruize-demos/monitoring/local_monitoring/bulk_demo
```
##### Execute the demo script in openshift as:
```sh
./bulk_service_demo.sh -c openshift
```

```
Usage: ./bulk_service_demo.sh [-s|-t] [-c cluster-type] [-l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image] [-k]
c = supports minikube, kind and openshift cluster-type
i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>
p = expose prometheus port
r = restart kruize only
l = deploy TFB app wih load
s = start (default), t = terminate
u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>
n = namespace of benchmark. Default - default
d = duration to run the benchmark load
k = install kruize using deploy scripts
```

Note: Kruize Operator doesn't support Bulk API yet, currently only non-operator deployment of Kruize `[-k]` is supported by Bulk demo. Stay tuned for more updates.

## Bulk API configuration

The user can modify the bulk API JSON configuration to specify or omit certain namespaces, workloads, or containers for which recommendations need to be generated.
Below is an example for generating recommendations for 'tfb-1' namespace 

### Bulk API configuration to generate recommendations only for the specified namespace

```json
{
  "filter": {
    "exclude": {
      "namespace": [],
      "workload": [],
      "containers": [],
      "labels": {}
    },
    "include": {
      "namespace": ["tfb-1"],
      "workload": [],
      "containers": [],
      "labels": {
        "key1": "value1",
        "key2": "value2"
      }
    }
  },
  "time_range": {}
  
}

```

Note: The option to filter based on namespaces and other criteria in the bulk configuration is not supported in Kruize release 0.1 and will be introduced in a future release.
