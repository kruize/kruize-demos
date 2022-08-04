# **HPO Scale tests**

  This test captures the HPO resource usage (cpu, memory, filesystem usage, network - receive / transmit bandwidth) of a single HPO instance by scaling the experiments from 1x to 100x for 5 trials and 3 iterations and computes the average, min and max values. 

## Supported Clusters
- Openshift, minikube

## Prerequisites for running the test:

- Minikube setup (To run this test on minikube)

## How to run the tests?

Use the below command to test:

```
cd <KRUIZE_DEMO_REPO>/scale_tests

./hpo_scale_tests.sh -c [ openshift|minikube ] [ -d results directory] [-s|-t] [-r] [-o hpo container image]
```

Where values for hpo_scale_tests.sh are:

```
usage: hpo_scale_tests.sh [ -c ] : cluster type. Supported types -  minikube, openshift
			[ -r ] : this will skip the prometheus setup & cloning of the required repositories
			[ -s | -t ] : start or terminate hpo, default is start hpo
			[ -o ] : optional. Container image for hpo, default is kruize/hpo:test
			[ -d ] : optional. Results directory location, by default it creates the results directory in current working directory

```

For example, to run the scale test on openshift execute the below command:
```
./hpo_scale_tests.sh -c openshift -o kruize/hpo:test -d /home/results
```
Note - resource usage details can be found in res_usage_output.csv in the results directory
