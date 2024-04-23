# Recommendation Validation Infrastructure

This script facilitates recommendation generation and validation through various modes and options. Below, we outline supported modes and available script options for users to customize their experience.

## Supported Modes
- Data-Driven Recommendations: Utilize existing data from ROS or in-house benchmarks. (--dataDrivenRecommendations)
- Cluster Monitoring: Gather live metrics for a specified cluster. (--monitorRecommendations)
- Demo Benchmark: Use metrics from demo benchmarks. (--demoBenchmark)
- Validation: Match recommendations with existing data. (--validate)
- Summarization: Summarize cluster and namespace data. (--summarize-clusters, --summarize-namespaces, --summarize-all)

## Script Options
```
Option                  Description

-o                      Kruize Docker image.
-p                      Enable Prometheus setup (default: disabled).
-r                      Restart Kruize only.
-s                      Start the demo (default: enabled).
-t                      Terminate the demo, cleaning up Kruize setup.
-c                      Specify cluster type (Supported: minikube/openshift).
-d                      Specify duration for demo or monitoring.
-a                      Use existing Kruize deployment and append experiments.
-u                      Enable Kruize recommendations to the demo app every 6 hours.
-g                      Get metrics recommendations.
-b                      Enable bulk results (default: disabled).
--mode=MODE             Specify mode (e.g., crc for CSV data with individual pod data).
--daysData=DAYS         Specify number of days of data to be pushed.
--dataDir=DIRECTORY     Specify data directory where CSV files exist.
--clusterName=NAME      Specify cluster name.
--namespaceName=NAME    Specify namespace name.
```

## Usage Examples

###  Generate Recommendations for ROS Data:

`./recommendations_demo.sh -c minikube -o quay.io/kruize/autotune_operator:0.0.19_rm --dataDrivenRecommendations --dataDir="./recommendations_demo/csv-data/" --mode=crc`

### Validate Recommendations for Existing CSV Files:
`./recommendations_demo.sh -c minikube -o quay.io/kruize/autotune_operator:0.0.19_rm --validate`

### Run Demo Benchmark:
`./recommendations_demo.sh -c minikube -o quay.io/kruize/autotune_operator:0.0.19_rm --demoBenchmark -d 24h`
This command runs a TFB demo benchmark on Minikube, collecting metrics every 15 minutes and pushing them to Kruize. The benchmark's duration is specified with -d.

### Enable Monitoring:
`./recommendations_demo.sh -c minikube -o quay.io/kruize/autotune_operator:0.0.19_rm --monitoring -d 24h --clusterName=<kruizerm.openshiftapps.com>`
Gathers metrics for a given cluster and pushes them to Kruize to generate recommendations.

### Summarize Available Data in Kruize:
`./recommendations_demo.sh -c minikube -o quay.io/kruize/autotune_operator:0.0.19_rm --summarize-all`
- summarize-clusters: Summarize cluster data. Default includes all clusters. Append --clusterName=<> and --namespaceName=<> for individual summaries.
- summarize-namespaces: Summarize namespace data. Default includes all namespaces. Append --namespaceName=<> for individual summaries.
- summarize-all: Summarize all data at both cluster and namespace levels.
