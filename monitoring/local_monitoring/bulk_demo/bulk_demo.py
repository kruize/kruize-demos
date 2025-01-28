"""
Copyright (c) 2024, 2024 Red Hat, IBM Corporation and others.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""
import getopt
import json
import os
import sys
import threading
import time
from contextlib import redirect_stdout
from time import sleep

from kruize.kruize import *


def generate_json(find_arr, json_file, filename, i):
    with open(json_file, 'r') as file:
        data = file.read()

    for find in find_arr:
        replace = find + "_" + str(i)
        data = data.replace(find, replace)

    with open(filename, 'w') as file:
        file.write(data)


def bulk_status(job_id):
    global status

    def thread_print(*args, **kwargs):
        with open(log_file, "a") as log:
            print(*args, **kwargs, file=log)

    # Get the bulk job status using the job id returned by Bulk API
    thread_print("\n#######################################")
    thread_print("Querying job status in a loop")
    thread_print("#######################################\n")
    include = "summary,experiments"
    response = get_bulk_job_status(job_id, include)
    if not response.text.strip():
        print(f"⚠️  Empty response from the server.")
        status = False
        return
    job_status_json = response.json()
    job_status = job_status_json['summary']['status']

    # Loop until job status is COMPLETED
    while job_status != "COMPLETED":
        response = get_bulk_job_status(job_id, include)
        if not response.text.strip():
            print("⚠️  Empty response from the server.")
            status = False
            return
        job_status_json = response.json()
        thread_print(
            f"Experiments: processed / Total -  {job_status_json['summary']['processed_experiments']} / {job_status_json['summary']['total_experiments']}")
        job_status = job_status_json['summary']['status']
        if job_status == "FAILED":
            thread_print("❌ Bulk Job FAILED due to this error: ", job_status_json['summary']['notifications'])
            thread_print("Check job_status.json for the job status")
            break
        sleep(10)

    # Dump the job status json into a file
    with open('job_status.json', 'w') as f:
        json.dump(job_status_json, f, indent=4)

    if job_status == "COMPLETED":
        print("✅ Complete!")
        print("🔄 Fetching the experiments...", end="")
        thread_print("\n#######################################")
        thread_print("Bulk Job Completed! Fetching the processed experiments and listing recommendations")
        thread_print("#######################################\n")

        exp_list = list(job_status_json["experiments"].keys())
        with open("experiment_list.txt", "w") as file:
            for exp in exp_list:
                file.write(exp + "\n")

        thread_print(f"Experiment names written to experiment_list.txt")
        # List recommendations for the experiments for which recommendations are available
        recommendations_json_arr = []

        # Hardcodig to reduce the time it takes to list all
        exp_count = 1
        counter = 0
        if exp_list != "":
            print("✅ Complete!")
            print(f"🔄 List the recommendations for {exp_count} experiments...", end="")
            for exp_name in exp_list:
                response = list_recommendations(exp_name)
                reco = response.json()
                recommendations_json_arr.append(reco)
                counter -= 1

                # Dump the recommendations into a json file
                with open('recommendations_data.json', 'w') as f:
                    json.dump(recommendations_json_arr, f, indent=4)
                print(".", end="")
                if counter <= 0:
                    break

            thread_print(f"Recommendations for {exp_count} container is available in recommendations_data.json")
            thread_print("List of all experiments are available in experiment_list.txt")
            print("✅ Complete!")
        else:
            thread_print("⚠️  Something went wrong! There are no experiments with recommendations!")
            print("⚠️  Something went wrong! There are no experiments with recommendations!")
        status = True
        return
    else:
        status = False
        return


def main(argv):
    cluster_type = "minikube"

    try:
        opts, args = getopt.getopt(argv, "h:c:d:")
    except getopt.GetoptError:
        print("bulk_demo.py -c <cluster type>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("bulk_demo.py -c <cluster type>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg

    with open(log_file, "a") as log:
        with redirect_stdout(log):
            print("bulk_demo.py -c %s" % (cluster_type))
            # Form the kruize url
            form_kruize_url(cluster_type)

    # Invoke the bulk service with the specified json
    print("🔄 Invoking bulk service...", end="")
    with open(log_file, "a") as log:
        with redirect_stdout(log):
            print("\n#######################################")
            print("Invoking bulk service")
            print("#######################################\n")
            bulk_json_file = "bulk_input.json"
            response = bulk(bulk_json_file)
            # Obtain the job id from the response from bulk service
            job_id_json = response.json()
            print("Response - ", job_id_json)
            job_id = job_id_json['job_id']
    print("✅ Invoked job_id", job_id)

    # Sleep for 10s initially to gather total experiments and failures
    time.sleep(10)

    include = "summary,experiments"
    response = get_bulk_job_status(job_id, include)
    job_status_json = response.json()
    total_experiments = job_status_json['summary']['total_experiments']
    job_status = job_status_json['summary']['status']
    if job_status == "FAILED":
        print(f"❌ Bulk Job FAILED with {job_status_json['summary']['notifications']}")
        print("📌 Job status is available in job_status.json\n")
        print("For detailed logs, look in kruize-bulk-demo.log")
        sys.exit(1)
    else:
        thread = threading.Thread(target=bulk_status, args=(job_id,))  # , daemon=False)
        thread.start()
        print(f"🔔 Bulk job experiment details are currently being updated in {log_file}.")
        # print("🔔 You can check job_status.log for ongoing updates as experiments are processed.")
        print(f"🔄 Processing {total_experiments} experiments. Please wait...", end="")

        while thread.is_alive():
            print(".", end="")
            time.sleep(60)

        if status:
            # print("✅ Completed!")
            print("📌 List of all experiments available in experiment_list.txt")
            print("📌 Recommendations for a single container in cluster can be found in recommendations_data.json.")
            print("📌 Job status is available in job_status.json\n")
        else:
            print("❌ Error while processing the job. Exiting!")
            print("📌 Job status is available in job_status.json\n")
            print("For detailed logs, look in kruize-bulk-demo.log")
            sys.exit(1)


log_file = os.getenv("LOG_FILE", "kruize-bulk-demo.log")
status = False
if __name__ == '__main__':
    main(sys.argv[1:])
