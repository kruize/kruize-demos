# Autotune Demo Scripts

Want to know more about Autotune ? You've come to the right place !

# What is Autotune ?

[Autotune](https://github.com/kruize/autotune/blob/master/README.md) is an Autonomous Performance Tuning Tool for Kubernetes. Autotune accepts a user provided "sla" goal to optimize application performance. It uses Prometheus to identify "layers" of an application that it is monitoring and matches tunables from those layers to the user provided sla. It then runs experiments with the help of a hyperparameter optimization framework to arrive at the most optimal values for the identified tunables to get a better result for the user provided sla.

Autotune can take an arbitrarily large set of tunables and run experiments to continually optimize the user provided sla in incremental steps. For this reason, it does not necessarily have a "best" value for a set of tunables, only a "better" one than what is currently deployed.

# [minikube demo](/minikube_demo_setup.sh)
- Goal
  - The user has an application that is deployed to minikube and is looking to improve some aspect of performance of the application. The user specifies an "objective function" in an "Autotune object" that defines the performance aspect of the application that needs to be optimized. Autotune then analyzes the user application, breaks it down into its component layers and provides tunables associated with each layer that can help optimize the user provided objective function.
- Steps
  - This demo installs Autotune along with Prometheus and Grafana to minikube. It also deploys two example REST CRUD applications, quakus galaxies and springboot petclinic, to the minikube cluster. It then deploys the "Autotune Objects" that define the objective function of the performance tuning that needs to be done for each application.
- pre-req
  - It expects minikube to be installed with atleast 8 CPUs and 16384MB Memory. 
- What it does not do
  - It does not kick off any experiments with the tunables (as yet). Stay tuned !!
- ##### WARNING: The script deletes any existing minikube cluster.

## What is an Objective Function ?
An objective function specifies a tuning goal in the form of a monitoring system (Eg Prometheus) query.
```
apiVersion: "recommender.com/v1"
kind: Autotune
metadata:
  name: "galaxies-autotune"
  namespace: "default"
spec:
  sla:
    objective_function: "request_sum/request_count"
    sla_class: "response_time"
    direction: "minimize"
    function_variables:
    - name: "request_sum"
      query: rate(http_server_requests_seconds_sum{method="GET",outcome="SUCCESS",status="200",uri="/galaxies",}[1m])
      datasource: "prometheus"
      value_type: "double"
    - name: "request_count"
      query: rate(http_server_requests_seconds_count{method="GET",outcome="SUCCESS",status="200",uri="/galaxies",}[1m])
      datasource: "prometheus"
      value_type: "double"
  mode: "show"
  selector:
    matchLabel: "app.kubernetes.io/name"
    matchLabelValue: "galaxies-deployment"
    matchRoute: ""
    matchURI: ""
    matchService: ""
```
In the above yaml from the [benchmarks](https://github.com/kruize/benchmarks/blob/master/galaxies/autotune/autotune-http_resp_time.yaml) repo, the overall goal or `sla` for the IT Admin is to minimize response time of the application deployment `galaxies-deployment`. The objective function defines what exactly constitutes response time. In this example it is a regular expression `request_sum/request_count`. The `function_variables` section helps to resolve the individual variables of the expression. In this case, `request_sum` represents the value returned by the prometheus query `rate(http_server_requests_seconds_sum{method="GET",outcome="SUCCESS",status="200",uri="/galaxies",}[1m])` and `request_count` represents the value returned by the prometheus query `rate(http_server_requests_seconds_count{method="GET",outcome="SUCCESS",status="200",uri="/galaxies",}[1m])`.

See the [benchmarks](https://github.com/kruize/benchmarks) repo for more examples on how to define Autotune objects. Look for ${benchmark_name}/autotune dir for example yamls.

## What is a Layer ?

A Layer is a software component of an application stack. In Autotune, we currently have 4 layers defined.
```
layer 0 = Container (Fixed and is always present)
layer 1 = Language Runtime (Eg. Hotspot JVM, Eclipse OpenJ9 JVM, nodejs...)
layer 2 = App Server / Framework (Quarkus, Liberty, Springboot...)
layer 3 = Application
```
A layer is defined by an `AutotuneConfig` object in Autotune. See the layer [template](https://github.com/kruize/autotune/blob/master/manifests/autotune-configs/layer-config.yaml_template) if you want to add a new layer.

## What is a Tunable ?

A tunable is a performance tuning knob specific to a layer. Autotune currently supports `double` and `integer` tunables. Tunables of these two types require a range to be specified in the form of a `upper_bound` and a `lower_bound`. This forms the valid range of values inside which the tunable operates. Tunables are defined in the `AutotuneConfig` object and are associated with a layer. Eg. The [Quarkus](https://github.com/kruize/autotune/blob/master/manifests/autotune-configs/quarkus-micrometer-config.yaml) `AutotuneConfig` yaml currently defines three tunables. See the layer [template](https://github.com/kruize/autotune/blob/master/manifests/autotune-configs/layer-config.yaml_template) if you want to add a new tunable.

## What is `sla_class` ?

`sla_class` is associated with a tunable and is one or more of `response_time`, `throughput` and `resource_usage`. It represents the impact a tunable has on the outcome for any given workload. For example, we know based on prior experiments that the [hotspot](https://github.com/kruize/autotune/blob/master/manifests/autotune-configs/hotspot-micrometer-config.yaml) tunable, `MaxInlineLevel` has an impact on both `throughput` and `response_time` but has a negligible impact on `resource_usage`.

