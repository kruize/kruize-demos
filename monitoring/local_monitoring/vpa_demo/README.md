# Kruize VPA Integration - "recreate" mode in Kruize

In Kruize's local `recreate` experiment mode, you can explore how recommendations are automatically applied using Vertical Pod Autoscaler (VPA) integration.

By integrating Kruize with Kubernetes' VPA, you can enable the automatic application of CPU and memory recommendations, optimizing resource utilization and efficiency.

When an experiment is created in `recreate` mode, Kruize automatically generates the corresponding VPA object, periodically updates recommendations, and patches the VPA object accordingly.


## Demo workflow

- Deploys Vertical Pod Autoscaler (VPA)
- Deploys sysbench as a demo workload
- Deploys Kruize and creates the metric profile
- Creates an `recreate` mode experiment using experiments/container_vpa_experiment_sysbench.json

To begin exploring the Kruize VPA Integration capabilities, follow these steps:

### Run the Demo

##### Clone the demo repository:
```sh
git clone git@github.com:kruize/kruize-demos.git
```
##### Change directory to the local monitoring demo:
```sh
cd kruize-demos/monitoring/local_monitoring/vpa_demo
```
##### Execute the demo script in openshift as:
```sh
./vpa_demo.sh -c openshift -i quay.io/rh-ee-shesaxen/autotune:vpa-0.2
```

```
Usage: ./bulk_service_demo.sh [-s|-t] [-c cluster-type] [-l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image]
c = supports minikube, kind and openshift cluster-type
i = kruize image.
p = expose prometheus port
r = restart kruize only
s = start (default), t = terminate
u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>
n = namespace of benchmark. Default - default
o = Kruize operator image. Default - quay.io/kruize/kruize-operator:<version as in Makefile>
k = install kruize using deploy scripts.
```

Refer the documentation of Kruize operator [Makefile](https://github.com/kruize/kruize-operator/blob/main/Makefile) for more details.

## Create Experiment JSON

The user can modify the create experiment JSON configuration to specify desired workloads.
Below is an example for 'sysbench' workload 

```json
[{
  "version": "v2.0",
  "experiment_name": "optimize-sysbench",
  "cluster_name": "default",
  "performance_profile": "resource-optimization-local-monitoring",
  "mode": "recreate",
  "target_cluster": "local",
  "datasource": "prometheus-1",
  "kubernetes_objects": [
    {
      "type": "deployment",
      "name": "sysbench",
      "namespace": "default",
      "containers": [
        {
          "container_image_name": "quay.io/kruizehub/sysbench",
          "container_name": "sysbench"
        }
      ]
    }
  ],
  "trial_settings": {
    "measurement_duration": "2min"
  },
  "recommendation_settings": {
    "threshold": "0.1"
  }
}]

```

Create experiment using -

```
curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json
```