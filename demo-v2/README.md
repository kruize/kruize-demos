# Kruize Demos v2 - Python Edition

> NOTE: THIS COMPARISION IS DONE BY BOB (AI GENERATED, NEEDS TO BE CAREFULLY REVIEWED)

A complete Python rewrite of Kruize demos with an interactive CLI interface for easier onboarding and usage.

## 🎯 Features

- **Interactive CLI**: User-friendly command-line interface with guided prompts
- **Multiple Demo Types**: Local monitoring, remote monitoring, bulk operations, and more
- **Cluster Support**: Works with Minikube, Kind, and OpenShift clusters
- **Configuration Management**: Easy-to-use configuration with sensible defaults
- **Rich Output**: Beautiful terminal output with progress indicators and status messages
- **Modular Design**: Clean, maintainable Python codebase

## 📋 Prerequisites

- Python 3.8 or higher
- One of the following Kubernetes clusters:
  - Minikube (with 8+ CPUs and 16GB+ RAM)
  - Kind
  - OpenShift
- kubectl or oc CLI tools
- Go 1.21+ (for operator deployment)

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/kruize/kruize-demos.git
cd kruize-demos/demo-v2

# Install dependencies
pip install -r requirements.txt

# Run the interactive CLI
python kruize_demo.py
```

### Basic Usage

```bash
# Interactive mode (recommended for new users)
python kruize_demo.py

# Direct command mode
python kruize_demo.py --demo local --cluster kind --setup

# List available demos
python kruize_demo.py --list

# Get help
python kruize_demo.py --help
```

## 📚 Available Demos

### 1. Local Monitoring Demo
Monitor and optimize workloads running in your local cluster.

```bash
python kruize_demo.py --demo local --cluster kind --setup
```

### 2. Remote Monitoring Demo
Create experiments and update results using Kruize REST APIs.

```bash
python kruize_demo.py --demo remote --cluster minikube
```

### 3. Bulk Demo
Process multiple experiments in bulk for large-scale optimization.

```bash
python kruize_demo.py --demo bulk --cluster openshift
```

### 4. GPU Demo
Optimize GPU-based workloads.

```bash
python kruize_demo.py --demo gpu --cluster openshift
```

### 5. VPA Demo
Vertical Pod Autoscaler integration demo.

```bash
python kruize_demo.py --demo vpa --cluster kind
```

### 6. Optimizer Demo
Advanced optimization scenarios.

```bash
python kruize_demo.py --demo optimizer --cluster minikube
```

### 7. Runtimes Demo
Runtime-specific optimization (Java, Node.js, etc.).

```bash
python kruize_demo.py --demo runtimes --cluster openshift
```

## 🎮 Interactive Mode

The interactive mode provides a guided experience:

1. **Select Demo Type**: Choose from available demos
2. **Configure Cluster**: Select cluster type and options
3. **Set Parameters**: Configure demo-specific parameters with defaults shown
4. **Review Configuration**: See all settings before execution
5. **Execute**: Run the demo with real-time progress updates

## ⚙️ Configuration

Configuration can be provided via:

1. **Interactive prompts** (default)
2. **Command-line arguments**
3. **Configuration file** (`config.yaml`)
4. **Environment variables**

### Example Configuration File

```yaml
# config.yaml
cluster:
  type: kind
  setup: true
  
kruize:
  image: quay.io/kruize/autotune_operator:latest
  ui_image: quay.io/kruize/kruize-ui:latest
  operator_image: quay.io/kruize/kruize-operator:latest
  use_operator: true

demo:
  namespace: default
  load_duration: 1200
  wait_time: 0
  expose_prometheus: false

logging:
  level: INFO
  file: kruize-demo.log
```

## 🔧 Advanced Options

### Custom Images

```bash
python kruize_demo.py --demo local \
  --kruize-image quay.io/kruize/autotune_operator:dev \
  --ui-image quay.io/kruize/kruize-ui:dev \
  --operator-image quay.io/kruize/kruize-operator:dev
```

### Benchmark Options

```bash
python kruize_demo.py --demo local \
  --deploy-benchmark \
  --run-load \
  --load-duration 1800
```

### Cleanup

```bash
python kruize_demo.py --demo local --terminate
```

## 📖 Documentation

- [Architecture](docs/architecture.md)
- [API Reference](docs/api.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Contributing](docs/contributing.md)

## 🐛 Troubleshooting

### Common Issues

1. **Cluster not found**: Ensure your cluster is running and kubectl/oc is configured
2. **Insufficient resources**: Check that your cluster meets minimum requirements
3. **Port conflicts**: Ensure ports 8080, 8081 are available

### Debug Mode

```bash
python kruize_demo.py --demo local --debug
```

### Logs

Check `kruize-demo.log` for detailed execution logs.

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](docs/contributing.md) for guidelines.

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](../LICENSE) for details.

## 🔗 Links

- [Kruize Project](https://github.com/kruize/autotune)
- [Documentation](https://kruize.github.io/autotune/)
- [Community](https://github.com/kruize/autotune/discussions)