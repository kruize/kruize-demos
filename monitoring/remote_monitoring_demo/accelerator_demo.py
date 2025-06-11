import copy
import json
import re
import signal
import subprocess
import logging
import sys
import os
import threading
import time
from datetime import datetime, timedelta

import requests

CREATE_EXPERIMENT = f"http://127.0.0.1:8080/createExperiment"
CREATE_METRICS_PROFILE = f"http://127.0.0.1:8080/createMetricProfile"
UPDATE_RESULTS = f"http://127.0.0.1:8080/updateResults"
CREATE_PP = f"http://127.0.0.1:8080/createPerformanceProfile"
UPDATE_RECOMMENDATIONS = f"http://127.0.0.1:8080/updateRecommendations"

log_file = 'kruize_gpu_rm_demo.log'
if os.path.exists(log_file):
    os.remove(log_file)

# Configure logging
logging.basicConfig(filename=log_file, level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s')


def install_autotune(autotune_repo_path, image="quay.io/bharathappali/exman:rm-accelerator-support"):
    scripts_path = os.path.join(autotune_repo_path, "scripts")
    os.chdir(scripts_path)

    print("Running ./scripts/prometheus_on_kind.sh", end='')
    prom_install_process = subprocess.Popen(
        [f'{scripts_path}/prometheus_on_kind.sh', '-as'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

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
    print(f"Running deploy.sh -c minikube -i {image}", end='')
    autotune_install_process = subprocess.Popen(
        [f'{autotune_repo_path}/deploy.sh', '-c', 'minikube', '-m', 'crc', '-i', image],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    while autotune_install_process.poll() is None:
        print('.', end='', flush=True)
        time.sleep(5)

    print(' Done.')
    stdout, stderr = autotune_install_process.communicate()
    logging.info(stdout.decode())
    if stderr:
        logging.error(stderr.decode())

    if autotune_install_process.returncode == 0:
        print(f"✓ deploy.sh -c minikube -i {image} completed successfully")
    else:
        print(f"✗ deploy.sh -c minikube -i {image} failed")
        sys.exit(1)


def check_tool(tool):
    logging.info(f"Checking for {tool}...")
    try:
        tool_path = None


        for path in ['/usr/bin', '/usr/local/bin']:
            if os.path.exists(f"{path}/{tool}"):
                tool_path = f"{path}/{tool}"
                break

        if tool_path is None:
            logging.error(f"{tool} is not installed or doesn't exist in /usr/bin or /usr/local/bin")
            return False

        if tool in ['kubectl']:
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


def generate_timestamp(base_time, offset_minutes):
    return (base_time + timedelta(minutes=offset_minutes)).isoformat() + "Z"


def main():
    program_start_time = time.time()
    print("Please check kruize_gpu_demo.log for complete log info")
    print("")
    print("")
    print("")
    print("Checking Pre-Requisites:")
    tools = ['git', 'kubectl']
    for tool in tools:
        if not check_tool(tool):
            print(f"    ✗ {tool} is not installed. Please try again after installing {tool}. Exiting!")
            sys.exit(1)

    org_path = os.getcwd()

    autotune_repo_url = "https://github.com/bharathappali/autotune.git"
    autotune_repo_name = "autotune"
    autotune_repo_branch = "rm-accelerator-support-4"
    if os.path.exists(autotune_repo_name):
        logging.info(f"Folder '{autotune_repo_name}' already exists. Skipping clone.")
        print(f"✓ '{autotune_repo_name}' already exists. Skipping clone.")
    else:
        clone_repo_branch(autotune_repo_url, autotune_repo_name, autotune_repo_branch)

    autotune_repo_path = os.path.join(os.getcwd(), autotune_repo_name)
    install_autotune(autotune_repo_path, image="quay.io/bharathappali/exman:rm-accelerator-support")
    os.chdir(org_path)

    port_forward_thread = threading.Thread(target=port_forward_kruize, daemon=True)
    port_forward_thread.start()

    print("Waiting for kruize port to be forwarded")
    for i in range(50):
        if check_kruize_health():
            break
        time.sleep(5)

    if not check_kruize_health():
        print("Exiting as kruize port is unavailable")
        sys.exit(1)

    metrics_profile_path = os.path.join(os.getcwd(), "json_files", "accelerator", "profiles", "perf", "resource_optimisation_openshift.json")
    metrics_data = read_json(metrics_profile_path)
    if metrics_data is None:
        print(f"✗ Error reading {metrics_profile_path}")
        return

    if not post_request(CREATE_PP, metrics_data, "Performance Profile"):
        print(f"✗ Error creating Metrics Profile")
        return


    exps = ['no_gpu', 'full_gpu', 'partition_gpu']
    for exp in exps:
        experiment_path = os.path.join(os.getcwd(), "json_files", "accelerator", "exps", f"{exp}_exp.json")
        experiment_data = read_json(experiment_path)
        if experiment_data is None:
            print(f"✗ Error reading {experiment_path}")
            return

        if not post_request(CREATE_EXPERIMENT, experiment_data, "Experiment"):
            print(f"✗ Error creating Experiment")
            return

    for exp in exps:
        results_path = os.path.join(os.getcwd(), "json_files", "accelerator", "results", f"{exp}.json")
        results_data = read_json(results_path)
        if results_data is None:
            print(f"✗ Error reading {results_data}")
            return

        num_intervals = 96
        interval_minutes = 15
        base_time = datetime.utcnow() - timedelta(hours=24)
        for i in range(num_intervals):
            updated_data = copy.deepcopy(results_data)

            start_time = generate_timestamp(base_time, i * interval_minutes)
            program_end_time = generate_timestamp(base_time, (i + 1) * interval_minutes)

            updated_data[0]["interval_start_time"] = start_time
            updated_data[0]["interval_end_time"] = program_end_time

            if not post_request(UPDATE_RESULTS, updated_data, "Update Results"):
                print(f"✗ Error creating result")

    # cleanup()

    print(" ⏳ Sleeping for 1 minute ", end='')
    for i in range(20):
        print('.', end='')
        time.sleep(2)
    print(" ✅ Done.")

    program_end_time = time.time()
    elapsed_time = program_end_time - program_start_time
    print(f"\n⏱️ Total execution time: {elapsed_time:.2f} seconds")

if __name__ == "__main__":
    main()