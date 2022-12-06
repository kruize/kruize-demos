# Kruize Remote Monitoring Demo

## Goal
The goal of this demo is to demonstrate the workflow of Kruize in Remote monitoring mode. The [demo](./demo.py)  script creates experiments using the [Kruize Remote Monitoring REST APIs](https://github.com/kruize/autotune/tree/mvp_demo/design/MonitoringModeAPI.md) for the specified deployment in a namespace and updates the results containing the resource usage metrics for the deployment. It then fetches and displays the Kruize recommendations for each of the experiments created.

## Steps
This demo installs Autotune along with Prometheus and Grafana to minikube. It then creates multiple experiments (10 experiments) by posting the input json to Kruize Monitoring REST APIs, updates the results for all the experiments and fetches the Kruize recommendations for each experiment and displays it.

## Pre-req
It expects minikube to be installed with atleast 8 CPUs and 16384MB Memory.

## How do I run it?

```
# To setup the demo, clone kruize repo, install prometheus and deploy kruize using the following commands:
$ git clone https://github.com/kruize/autotune.git

# Install Prometheus using the below command:
$ cd autotune
$ ./scripts/prometheus_on_minikube.sh -as

# Deploy kruize using the below command:
$ ./deploy -i [kruize autotune operator image]

# Run the Kruize monitoring demo using the below command:
$ python demo.py -c [cluster type] -i [No. of experiments] -i [input json] -r [result json]

Where values for demo.py are:
usage: demo.py [ -c ] : cluster type. Supported types - minikube, openshift, default is minikube
	       [ -n] : No. of experiments, default is 10
	       [ -i ] : path to the input json file to create an experiment, default input.json
	       [ -r ] : path to the result json file to create an experiment, default input.json

To run this demo with the default values use the below command:
$ python demo.py

```

