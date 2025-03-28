import argparse
import json
import re
import signal
import subprocess
import logging
import sys
import os
import threading
import time

import requests

NODE_NAME = "kind-e2e-control-plane"
SAMPLE_WORKLOAD = "sample_workload.yaml"

CREATE_METRICS_PROFILE = f"http://127.0.0.1:8080/createMetricProfile"
CREATE_METADATA_PROFILE = f"http://127.0.0.1:8080/createMetadataProfile"
CREATE_EXPERIMENT = f"http://127.0.0.1:8080/createExperiment"

# Input folder
INPUT_FOLDER = "inputs"

# File paths
metrics_profile_path = os.path.join(os.getcwd(), INPUT_FOLDER, "metrics_profile.json")
metadata_profile_path = os.path.join(os.getcwd(), INPUT_FOLDER, "metadata_profile.json")
experiment_path = os.path.join(os.getcwd(), INPUT_FOLDER, "create_exp.json")

gopath = subprocess.check_output(['go', 'env', 'GOPATH'], text=True).strip()

# Update the PATH environment variable
go_bin_path = os.path.join(gopath, 'bin')
os.environ['PATH'] = os.environ['PATH'] + os.pathsep + go_bin_path

log_file = 'kruize_gpu_demo.log'
if os.path.exists(log_file):
    os.remove(log_file)

# Configure logging
logging.basicConfig(filename=log_file, level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s')

os.environ['PATH'] += ':/usr/bin:/usr/local/bin'


def read_json(file_path):
    try:
        with open(file_path, "r") as file:
            return json.load(file)
    except Exception as e:
        print(f" ✗ Error reading {file_path}: {e}")
        return None


def post_request(url, json_data, name):
    try:
        response = requests.post(url, json=json_data)
        if 200 <= response.status_code <= 299:
            print(f" ✓ Successfully created {name}")
            return True
        else:
            print(f" ✗ Failed to create {name} (Status: {response.status_code}): {response.text}")
            return False
    except Exception as e:
        print(f" ✗ Error sending request to {name}: {e}")
        return False


def check_tool(tool):
    logging.info(f"Checking for {tool}...")
    try:
        tool_path = None

        if tool == 'ginkgo':
            if os.path.exists(f"{go_bin_path}/{tool}"):
                tool_path = f"{go_bin_path}/{tool}"
        else:
            for path in ['/usr/bin', '/usr/local/bin']:
                if os.path.exists(f"{path}/{tool}"):
                    tool_path = f"{path}/{tool}"
                    break

        if tool_path is None:
            logging.error(f"{tool} is not installed or doesn't exist in /usr/bin or /usr/local/bin")
            return False

        if tool in ['kubectl', 'helm', 'go', 'ginkgo']:
            subprocess.run([f"{tool_path}", 'help'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        else:
            subprocess.run([f"{tool_path}", '--help'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        print(f"    ✓ {tool} is available on system")
        return True
    except subprocess.CalledProcessError:
        logging.error(f"{tool} is not installed or not in PATH")
        return False


def clone_repo(repo_url, repo_name):
    logging.info(f"Cloning {repo_url}...")
    try:
        subprocess.run(['git', 'clone', repo_url], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print(f"✓ {repo_name} cloned")
        logging.info(f"{repo_name} cloned successfully")
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to clone {repo_name}: {e}")
        sys.exit(1)


def clone_repo_branch(repo_url, repo_name, branch_name):
    """
    Clones a specific branch from a Git repository.

    :param repo_url: URL of the repository to clone
    :param repo_name: Name of the repository for logging
    :param branch_name: Branch to clone
    """
    logging.info(f"Cloning branch '{branch_name}' from {repo_url}...")
    try:
        subprocess.run(
            ['git', 'clone', '-b', branch_name, repo_url],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        print(f"✓ {repo_name} branch '{branch_name}' cloned")
        logging.info(f"{repo_name} branch '{branch_name}' cloned successfully")
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to clone branch '{branch_name}' of {repo_name}: {e.stderr.decode()}")
        sys.exit(1)


def update_manager_yml(instaslice_repo_path):
    manager_yml_path = os.path.join(instaslice_repo_path, "config", "manager", "manager.yaml")

    if not os.path.exists(manager_yml_path):
        print(f"Error: {manager_yml_path} does not exist.")
        sys.exit(1)
    try:
        with open(manager_yml_path, 'r') as file:
            lines = file.readlines()

        with open(manager_yml_path, 'w') as file:
            for line in lines:
                if "runAsNonRoot: true" in line:
                    file.write(line.replace("runAsNonRoot: true", "runAsNonRoot: false"))
                else:
                    file.write(line)

        print(f"✓ Updated {manager_yml_path} successfully.")
    except FileNotFoundError:
        print(f"✗ Error: {manager_yml_path} not found.")
        sys.exit(1)
    except Exception as e:
        print(f"✗ An error occurred while updating {manager_yml_path}: {e}")
        sys.exit(1)


def run_make_test(repo_path, env_vars_passed):
    os.chdir(repo_path)

    update_manager_yml(instaslice_repo_path=repo_path)

    print("Running make test-e2e-kind-emulated ", end='')
    logging.info("Running make test-e2e-kind-emulated...")

    env_vars = os.environ.copy()
    env_vars['IMG'] = env_vars_passed['CNTRL']
    env_vars['IMG_DMST'] = env_vars_passed['DMST']
    process = subprocess.Popen(['make', 'test-e2e-kind-emulated'],
                               env=env_vars,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)

    while process.poll() is None:
        print('.', end='', flush=True)
        time.sleep(5)

    print(' Done.')
    stdout, stderr = process.communicate()
    logging.info(stdout.decode())
    if stderr:
        logging.error(stderr.decode())

    if process.returncode == 0:
        print("✓ make test-e2e-kind-emulated completed successfully")
    else:
        print("✗ make test-e2e-kind-emulated failed")
        sys.exit(1)


def install_fake_gpu_operator(fake_gpu_operator_repo_path):
    os.chdir(fake_gpu_operator_repo_path)
    try:
        subprocess.run(
            ['kubectl', 'label', 'node', NODE_NAME, 'run.ai/simulated-gpu-node-pool=default'],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to label node '{NODE_NAME}': {e.stderr.decode()}")
        sys.exit(1)

    commands = [
        ["helm", "repo", "add", "fake-gpu-operator", "https://fake-gpu-operator.storage.googleapis.com"],
        ["helm", "repo", "update"],
        [
            "helm", "upgrade", "-i", "gpu-operator", "fake-gpu-operator/fake-gpu-operator",
            "--namespace", "gpu-operator", "--create-namespace"
        ]
    ]

    for cmd in commands:
        try:
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            logging.info(f"Command '{' '.join(cmd)}' executed successfully.")
        except subprocess.CalledProcessError as e:
            logging.error(f"Command '{' '.join(cmd)}' failed with error: {e}")


def install_autotune(autotune_repo_path):
    scripts_path = os.path.join(autotune_repo_path, "scripts")
    os.chdir(scripts_path)

    print("Running ./scripts/prometheus_on_kind.sh", end='')
    prom_install_process = subprocess.Popen([f'{scripts_path}/prometheus_on_kind.sh', '-as'], stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE)

    while prom_install_process.poll() is None:
        print('.', end='', flush=True)
        time.sleep(5)

    print(' Done.')
    stdout, stderr = prom_install_process.communicate()
    logging.info(stdout.decode())
    if stderr:
        logging.error(stderr.decode())

    if prom_install_process.returncode == 0:
        print("✓ ./scripts/prometheus_on_kind.sh completed successfully")
    else:
        print("✗ ./scripts/prometheus_on_kind.sh failed")
        sys.exit(1)

    os.chdir(autotune_repo_path)
    print("Running deploy.sh -c minikube -i quay.io/bharathappali/exman:gpu-demo-local", end='')
    autotune_install_process = subprocess.Popen([f'{autotune_repo_path}/deploy.sh', '-c', 'minikube', '-m', 'crc', '-i',
                                                 'quay.io/bharathappali/exman:gpu-demo-local'],
                                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    while autotune_install_process.poll() is None:
        print('.', end='', flush=True)
        time.sleep(5)

    print(' Done.')
    stdout, stderr = autotune_install_process.communicate()
    logging.info(stdout.decode())
    if stderr:
        logging.error(stderr.decode())

    if autotune_install_process.returncode == 0:
        print("✓ deploy.sh -c minikube -i quay.io/bharathappali/exman:gpu-demo-local completed successfully")
    else:
        print("✗ deploy.sh -c minikube -i quay.io/bharathappali/exman:gpu-demo-local failed")
        sys.exit(1)


def apply_sample_workload(manifests_path):
    sample_workload_path = os.path.join(manifests_path, SAMPLE_WORKLOAD)

    if not os.path.exists(sample_workload_path):
        print(f"✗ Error: {sample_workload_path} does not exist.")
        sys.exit(1)

    try:
        subprocess.run(["kubectl", "apply", "-f", sample_workload_path], check=True)
        print(f"✓ Applied {sample_workload_path}")
    except subprocess.CalledProcessError as e:
        print(f"✗ Error applying {sample_workload_path}: {e}")
        sys.exit(1)


port_forward_process = None


def start_port_forward():
    global port_forward_process

    if port_forward_process:
        logging.info("🛑 Terminating previous port-forward process...")
        os.killpg(os.getpgid(port_forward_process.pid), signal.SIGTERM)
        time.sleep(5)

    logging.info("🔄 Starting port-forwarding for kruize service ...")

    port_forward_process = subprocess.Popen(
        ['kubectl', 'port-forward', '-n', 'monitoring', 'service/kruize', '8080:8080'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid  # Ensure process does not exit when Python exits
    )

    # Wait a few seconds to ensure it's running
    time.sleep(3)


def check_kruize_health():
    try:
        response = requests.get("http://127.0.0.1:8080/health", timeout=2)
        print(response.text)
        return 200 <= response.status_code <= 299
    except requests.exceptions.RequestException:
        return False


def port_forward_kruize():
    max_retries = 50

    for i in range(max_retries):
        logging.info(f"🛠️ Attempt {i + 1}/{max_retries} to port-forward...")

        start_port_forward()

        if check_kruize_health():
            print("✅ Port-forwarding successful and running in the background!")
            return

        logging.info("❌ Port-forwarding failed, retrying in 5 seconds...")
        time.sleep(5)

    print("🚨 Reached max retries. Exiting.")
    sys.exit(1)


def cleanup():
    global port_forward_process
    print("🛑 Cleaning up...")

    if port_forward_process:
        os.killpg(os.getpgid(port_forward_process.pid), signal.SIGTERM)


def check_ral_pod(pod_identifier, namespace):
    try:
        result = subprocess.run(
            ["kubectl", "get", "pods", "-n", namespace, "--no-headers", "-o", "custom-columns=:metadata.name"],
            capture_output=True,
            text=True
        )
        pod_names = [line.strip() for line in result.stdout.splitlines() if pod_identifier in line]

        if not pod_names:
            print(f" ✗ No pod found with identifier '{pod_identifier}' in namespace '{namespace}'")
            return

        for pod_name in pod_names:
            print("----------------------------------------------------------------------")
            print(f"Checking requests and limits for pod: {pod_name}")

            # Get the full pod description
            describe_result = subprocess.run(
                ["kubectl", "describe", "pod", pod_name, "-n", namespace],
                capture_output=True,
                text=True,
                check=True
            )

            capture = False
            lines_to_capture = 0
            relevant_lines = []

            for line in describe_result.stdout.splitlines():
                line = line.strip()

                if line.startswith("Requests:") or line.startswith("Limits:"):
                    capture = True
                    lines_to_capture = 10  # Reset capture limit
                    relevant_lines.append(line)  # Store header

                elif capture and lines_to_capture > 0:
                    if re.search(r"\b(cpu|memory|nvidia.com/gpu|instaslice)\b", line):
                        relevant_lines.append(line)
                    lines_to_capture -= 1

                elif lines_to_capture == 0:
                    capture = False  # Stop capturing after 10 lines

            # Print the filtered output
            if relevant_lines:
                print("\n".join(relevant_lines))
            else:
                print("✗ No requests or limits found.")
            print("----------------------------------------------------------------------")
    except subprocess.CalledProcessError as e:
        print(f" ✗ Error running kubectl command: {e}")


def main():
    start_time = time.time()
    print("Please check kruize_gpu_demo.log for complete log info")
    print("")
    print("")
    print("")
    print("Checking Pre-Requisites:")
    tools = ['go', 'ginkgo', 'make', 'git', 'kubectl', 'helm']
    for tool in tools:
        if not check_tool(tool):
            print(f"    ✗ {tool} is not installed. Please try again after installing {tool}. Exiting!")
            sys.exit(1)

    parser = argparse.ArgumentParser(description="Configure InstaSlice images dynamically.")

    parser.add_argument(
        "--insta-cntrl",
        type=str,
        default="quay.io/bharathappali/instaslice:test-e2e-cntrl",
        help="Image for InstaSlice controller (default: quay.io/bharathappali/instaslice:test-e2e-cntrl)"
    )

    parser.add_argument(
        "--insta-dmst",
        type=str,
        default="quay.io/bharathappali/instaslice:test-e2e-dmnst",
        help="Image for InstaSlice daemonset (default: quay.io/bharathappali/instaslice:test-e2e-dmnst)"
    )

    args = parser.parse_args()

    env_vars = {
        'CNTRL': args.insta_cntrl,
        'DMST': args.insta_dmst
    }

    print("Using the following image configurations:")
    print(f"Controller Image: {env_vars['IMG']}")
    print(f"Daemonset Image: {env_vars['IMG_DMST']}")

    instaslice_repo_url = "https://github.com/openshift/instaslice-operator.git"
    instaslice_repo_name = "instaslice-operator"
    if os.path.exists(instaslice_repo_name):
        logging.info(f"Folder '{instaslice_repo_name}' already exists. Skipping clone.")
        print(f"✓ '{instaslice_repo_name}' already exists. Skipping clone.")
    else:
        clone_repo(instaslice_repo_url, instaslice_repo_name)

    org_path = os.getcwd()
    instaslice_repo_path = os.path.join(os.getcwd(), instaslice_repo_name)
    run_make_test(instaslice_repo_path, env_vars_passed=env_vars)
    os.chdir(org_path)

    fake_gpu_operator_repo_url = "https://github.com/run-ai/fake-gpu-operator.git"
    fake_gpu_operator_repo_name = "fake-gpu-operator"
    if os.path.exists(fake_gpu_operator_repo_name):
        logging.info(f"Folder '{fake_gpu_operator_repo_name}' already exists. Skipping clone.")
        print(f"✓ '{fake_gpu_operator_repo_name}' already exists. Skipping clone.")
    else:
        clone_repo(fake_gpu_operator_repo_url, fake_gpu_operator_repo_name)

    fake_gpu_operator_repo_path = os.path.join(os.getcwd(), fake_gpu_operator_repo_name)
    install_fake_gpu_operator(fake_gpu_operator_repo_path)
    os.chdir(org_path)

    autotune_repo_url = "https://github.com/bharathappali/autotune.git"
    autotune_repo_name = "autotune"
    autotune_repo_branch = "gpu-demo-local"
    if os.path.exists(autotune_repo_name):
        logging.info(f"Folder '{autotune_repo_name}' already exists. Skipping clone.")
        print(f"✓ '{autotune_repo_name}' already exists. Skipping clone.")
    else:
        clone_repo_branch(autotune_repo_url, autotune_repo_name, autotune_repo_branch)

    autotune_repo_path = os.path.join(os.getcwd(), autotune_repo_name)
    install_autotune(autotune_repo_path)
    os.chdir(org_path)

    port_forward_thread = threading.Thread(target=port_forward_kruize, daemon=True)
    port_forward_thread.start()

    manifests_dir_name = "manifests"
    manifests_path = os.path.join(os.getcwd(), manifests_dir_name)
    apply_sample_workload(manifests_path)

    print("Waiting for 30 secs for workload to start ", end="")
    for i in range(30):
        print(".", end="")
        time.sleep(1)
    print(" Done.")

    print("Checking pods in Default namespace")
    print("")
    print("")

    result = subprocess.run(
        ["kubectl", "get", "pods", "-n", "default"],
        capture_output=True,
        text=True
    )

    print(result.stdout)

    check_ral_pod(pod_identifier="sleepy-job", namespace="default")

    print("Waiting for kruize port to be forwarded")
    for i in range(50):
        if check_kruize_health():
            break
        time.sleep(5)

    if not check_kruize_health():
        print("Exiting as kruize port is unavailable")
        sys.exit(1)

    metrics_data = read_json(metrics_profile_path)
    if metrics_data is None:
        print(f"✗ Error reading {metrics_profile_path}")
        return

    if not post_request(CREATE_METRICS_PROFILE, metrics_data, "Metric Profile"):
        print(f"✗ Error creating Metrics Profile")
        return

    metadata_profile_data = read_json(metadata_profile_path)
    if metadata_profile_data is None:
        print(f"✗ Error reading {metadata_profile_path}")
        return

    if not post_request(CREATE_METADATA_PROFILE, metadata_profile_data, "Metadata Profile"):
        print(f"✗ Error creating Metadata Profile")
        return

    experiment_data = read_json(experiment_path)
    if experiment_data is None:
        print(f"✗ Error reading {experiment_path}")
        return

    if not post_request(CREATE_EXPERIMENT, experiment_data, "Experiment"):
        print(f"✗ Error creating Experiment")
        return

    cleanup()

    print(" ⏳ Sleeping for 1 minute ", end='')
    for i in range(20):
        print('.', end='')
        time.sleep(2)
    print(" ✅ Done.")

    check_ral_pod(pod_identifier="sleepy-job", namespace="default")

    end_time = time.time()
    elapsed_time = end_time - start_time
    print(f"\n⏱️ Total execution time: {elapsed_time:.2f} seconds")


if __name__ == "__main__":
    main()
