# Experiment Templates

This directory contains experiment JSON templates for Kruize local monitoring demos.

## Templates

### 1. Container Experiment Template
**File:** `container_experiment_template.json`
- **Type:** Container-level monitoring
- **Measurement Duration:** 1 minute (for faster recommendations)
- **Placeholders:**
  - `PLACEHOLDER_CONTAINER` - Container name
  - `PLACEHOLDER_WORKLOAD` - Workload/deployment name
  - `PLACEHOLDER_WORKLOAD_TYPE` - Workload type (deployment, statefulset, etc.)
  - `PLACEHOLDER_NAMESPACE_NAME` - Namespace
  - `PLACEHOLDER_IMAGE` - Container image

### 2. Namespace Experiment Template
**File:** `namespace_experiment_template.json`
- **Type:** Namespace-level monitoring
- **Measurement Duration:** 1 minute (for faster recommendations)
- **Placeholders:**
  - `PLACEHOLDER_NAMESPACE_NAME` - Namespace to monitor

## Dynamic Experiment Generation

The demo automatically generates experiments from these templates by replacing placeholders with actual values based on deployed workloads.

### Example: Generating Container Experiment

```python
from demo-v2.demos.local_monitoring import LocalMonitoringDemo

# Template will be filled with:
# - PLACEHOLDER_CONTAINER -> "sysbench"
# - PLACEHOLDER_WORKLOAD -> "sysbench"
# - PLACEHOLDER_WORKLOAD_TYPE -> "deployment"
# - PLACEHOLDER_NAMESPACE_NAME -> "default"
# - PLACEHOLDER_IMAGE -> "quay.io/kruizehub/sysbench"

# Result: monitor_container_sysbench experiment
```

### Example: Generating Namespace Experiment

```python
# Template will be filled with:
# - PLACEHOLDER_NAMESPACE_NAME -> "default"

# Result: monitor_namespace_default experiment
```

## Benchmark to Experiment Mapping

The demo automatically creates experiments for deployed benchmarks:

| Benchmark | Container Experiments | Namespace Experiment |
|-----------|----------------------|---------------------|
| sysbench | monitor_container_sysbench | monitor_namespace_default |
| tfb | monitor_container_tfb-server, monitor_container_tfb-database | monitor_namespace_default |
| petclinic | monitor_container_petclinic | monitor_namespace_default |

## Measurement Duration

All experiments use **1 minute** measurement duration to enable:
- Faster data collection
- Recommendations available in ~2 minutes (after 2 data points)
- Quick demo turnaround

## Experiment JSON Format

All experiments follow the Kruize v2.0 format and are wrapped in an array:

```json
[{
  "version": "v2.0",
  "experiment_name": "your_experiment_name",
  "cluster_name": "default",
  "performance_profile": "resource-optimization-local-monitoring",
  "metadata_profile": "cluster-metadata-local-monitoring",
  "mode": "monitor",
  "target_cluster": "local",
  "datasource": "prometheus-1",
  "kubernetes_objects": [...],
  "trial_settings": {
    "measurement_duration": "1min"
  },
  "recommendation_settings": {
    "threshold": "0.1"
  }
}]
```

## Usage

The demo automatically:
1. Detects deployed benchmarks
2. Loads appropriate template (container or namespace)
3. Replaces placeholders with actual values
4. Creates experiments in Kruize

No manual experiment creation needed!