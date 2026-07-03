# Kruize Optimizer Demo

This demo showcases the Kruize optimizer functionality for resource optimization in Kubernetes environments.

## Overview

The optimizer demo sets up and demonstrates Kruize Optimizers's ability to configure Kruize layers and profiles automatically and handle automatic experiment creation for labelled workloads. It supports multiple cluster types and can be configured with custom images.

## Prerequisites

- Go (required for operator deployment)
- One of the following cluster types:
  - Minikube
  - Kind
  - OpenShift

## Usage

```bash
./optimizer_demo.sh [-t] [-c cluster-type] [-f] [-i kruize-image] [-u kruize-ui-image] [-o kruize-operator-image] [-p optimizer-image] [-n namespace] [-k]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-s` | Start the demo | Enabled by default |
| `-t` | Terminate the demo | - |
| `-c` | Cluster type (minikube, kind, openshift) | `kind` |
| `-f` | Create environment setup for minikube/kind | - |
| `-i` | Custom Kruize image | `quay.io/kruize/autotune_operator:<version>` |
| `-u` | Custom Kruize UI image | `quay.io/kruize/kruize-ui:<version>` |
| `-o` | Custom Kruize operator image | `quay.io/kruize/kruize-operator:<version>` |
| `-g` | Specify Kruize operator git branch to clone | `main` |
| `-p` | Custom Kruize optimizer image | `quay.io/kruize/kruize-optimizer:0.0.1` |
| `-n` | Namespace for benchmark | `default` |
| `-k` | Disable operator and use deploy scripts | - |

## Examples

### Start demo with default settings (Kind cluster)
```bash
./optimizer_demo.sh
```

### Start demo on Minikube with environment setup
```bash
./optimizer_demo.sh -c minikube -f
```

### Start demo on OpenShift
```bash
./optimizer_demo.sh -c openshift
```

### Start demo with custom Kruize image
```bash
./optimizer_demo.sh -i quay.io/myrepo/autotune_operator:custom-tag
```

### Start demo without operator (using deploy scripts)
```bash
./optimizer_demo.sh -k
```

### Terminate the demo
```bash
./optimizer_demo.sh -t
```

## Configuration

### Benchmark Settings

This demo automatically installs the following benchmarks:
- sysbench
- tfb

### Optimizer Label

The demo automatically adds the label `kruize.io/optimizer: enabled` to all benchmark deployments.
Optimizer automatically creates experiments for workloads with the above label. 

## Experiments

The demo runs the following experiment:
```
Experiment 1: sysbench
- Name:      prometheus-1|default|default|sysbench(deployment)|sysbench
- Type:      deployment
- Namespace: default
- Container: sysbench

Experiment 2: tfb-qrh-sample
- Name:      prometheus-1|default|default|tfb-qrh-sample(deployment)|tfb-server
- Type:      deployment
- Namespace: default
- Container: tfb-server
``` 

## Logs

Detailed logs are written to `optimizer-demo.log` in the current directory. Recommendations are also logged in log file. 

## Architecture

The demo can run in two modes:

1. **Operator Mode** (default): Deploys Kruize using the Kubernetes operator
2. **Deploy Script Mode** (with `-k` flag): Deploys Kruize using deployment scripts

## Troubleshooting

- Check `optimizer-demo.log` for detailed error messages
- Ensure Go is installed if using operator mode
- Verify cluster is running and accessible
- Ensure required ports (8080, 8081) are available for port-forwarding

## Related Files

- `optimizer-demo.log` - Detailed execution logs
- `../common.sh` - Common utility functions
- `../../../common/common_helper.sh` - Common helper utilities

## Cleanup

To clean up the demo, run the following command:

```
./optimizer-demo.sh -t -c [cluster-type]
```
