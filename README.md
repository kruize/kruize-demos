# Kruize Demo Scripts

Want to try out Kruize? You've come to the right place!

## Available Demos

### 🔍 Local Monitoring Demo
Monitor your applications within your own environment and generate resource optimization recommendations by deploying Kruize locally. This demo showcases Kruize's ability to provide actionable recommendations at container and namespace level based on application performance.

**[Get Started with Local Monitoring](monitoring/local_monitoring/)**

### 📊 VPA Integration Demo
Explore Kruize's integration with Kubernetes Vertical Pod Autoscaler (VPA) in "recreate" mode. This demo demonstrates how Kruize automatically generates and applies CPU and memory recommendations through VPA, enabling automatic resource optimization with minimal manual intervention.

**[Get Started with VPA Demo](monitoring/local_monitoring/vpa_demo/)**

### 🚀 Bulk API Demo
Experience Kruize's Bulk API capabilities for generating resource optimization recommendations at scale. The Bulk API is designed to provide recommendations in bulk for all available containers, namespaces, and workloads across your cluster, making it ideal for large-scale deployments.

**[Get Started with Bulk Demo](monitoring/local_monitoring/bulk_demo/)**

## Info about Kruize repositories

- [kruize-demos](https://github.com/kruize/kruize-demos)
  This repo.
- [autotune](https://github.com/kruize/autotune)
  Main repo for Autotune sources.
- [benchmarks](https://github.com/kruize/benchmarks)
  Benchmark scripts for running performance tests with Autotune.
- [autotune-results](https://github.com/kruize/autotune-results)
  Results of experiments run with Autotune.
- [hpo](https://github.com/kruize/hpo)
  HPO as a Service.
