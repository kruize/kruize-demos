# **Kruize GPU Demo (NO GPU Scenario for testing kruize + instaslice integration)**

This script automates the installation and testing of **InstaSlice**, a **Fake GPU Operator**, and **Kruize** for dynamic GPU resource optimization. It runs an experimental workload, applies changes based on recommendations, and compares resource requests/limits before and after optimization.

---

## **Overview of the Script**

### **1. Setting Up Environment Variables**
The script defines key environment variables needed for execution:

- **`NODE_NAME`** → Specifies the Kubernetes node where workloads will run.
- **`SAMPLE_WORKLOAD`** → The YAML file that defines the dummy GPU workload.
- **API URLs**:
    - **`CREATE_METRICS_PROFILE`** → Endpoint to create a metrics profile in Kruize.
    - **`CREATE_EXPERIMENT`** → Endpoint to create a tuning experiment in Kruize.
- **File Paths**:
    - **`INPUT_FOLDER`** → The directory containing input JSON files.
    - **`metrics_profile_path`** → Path to the metrics profile JSON file.
    - **`experiment_path`** → Path to the experiment JSON file.

Additionally, the script sets up the **Go environment**:
- It fetches the Go **GOPATH** and updates the system **PATH** to include Go binaries.

---

### **2. Setting Up Logging and Cleaning Up Previous Runs**
- The script configures logging to a file (`kruize_gpu_demo.log`).
- If an existing log file is present, it is removed to ensure fresh logs for the new run.
- The system **PATH** is updated to include `/usr/bin` and `/usr/local/bin` for tool execution.

---

### **3. Validating Required Tools**
The script checks for essential tools required for the workflow:
- **`kubectl`** → Manages Kubernetes resources.
- **`helm`** → Installs and manages Helm charts.
- **`go`** → Required for Go-based applications.
- **`ginkgo`** → Used for running Go-based tests.

If any of these are missing, the script logs an error and exits.

To install `ginkgo` please check your golang version and find a `ginkgo` version which fits and run this command,
Replace the appropriate version / link

```shell
go install github.com/onsi/ginkgo/v2/ginkgo@latest
```

---

### **4. Cloning Repositories**
The script clones necessary repositories from GitHub:
- **InstaSlice** → A tool for dynamic GPU partitioning. [Repo Link](https://github.com/openshift/instaslice-operator/)
- **Fake GPU Operator** → A simulated GPU environment for Kubernetes. [Repo Link](https://github.com/run-ai/fake-gpu-operator)

If a specific branch is required, the script clones that branch.

---

### **5. Updating Configuration Files**
- The script **modifies `manager.yaml`** inside the InstaSlice repository.
- Specifically, it changes **`runAsNonRoot: true`** to **`runAsNonRoot: false`** to allow proper execution.

This step ensures that the operator can run in environments where `runAsNonRoot` enforcement is problematic.

---

### **6. Running InstaSlice End-to-End Tests**
- The script navigates to the InstaSlice repository and runs **`make test-e2e-kind-emulated`**.
- It sets environment variables like:
    - **`IMG`** → Specifies the container image for the control plane.
    - **`IMG_DMST`** → Specifies the container image for the daemonset.
- The test runs in a **Kind** (Kubernetes-in-Docker) cluster.

The script continuously monitors the test execution and logs its progress.

---

### **7. Installing the Fake GPU Operator**
- Labels the **Kubernetes node** to simulate a GPU node.
- Installs the **Fake GPU Operator** using Helm.
    - It first **adds the Helm repository**.
    - Then, it **updates Helm charts**.
    - Finally, it **deploys the Fake GPU Operator** into the `gpu-operator` namespace.

This allows us to run GPU workloads in Kubernetes without physical GPUs.

---

### **8. Deploying the Sample GPU Workload**
- The script applies **`sample_workload.yaml`** to Kubernetes.
- This workload requests GPU resources and runs in the cluster.

---

### **9. Running Kruize for Resource Optimization**
- The script reads **metrics profile JSON** and **experiment JSON** files.
- It sends **POST requests** to Kruize's API:
    - First, it **registers the metrics profile**.
    - Then, it **creates an experiment** for resource tuning.

---

### **10. Fetching and Applying Optimization Recommendations**
- Kruize provides optimized **requests and limits** for resource usage.
- The script retrieves these recommendations.
- It applies them to the workload to **improve resource efficiency**.

---

### **11. Comparing Resource Requests and Limits (Before vs. After)**
- The script logs the **original** requests and limits.
- After Kruize updates the resources, it logs the **new** optimized values.
- This comparison shows how Kruize dynamically **improves resource allocation**.

---

## **Conclusion**
This script automates the full cycle of:
1. **Installing a GPU partitioning tool (InstaSlice).**
2. **Setting up a simulated GPU environment.**
3. **Deploying and testing GPU workloads.**
4. **Creating Experiment in Kruize and apply recommendations**
5. **Displaying the improvements in resource allocation.**

