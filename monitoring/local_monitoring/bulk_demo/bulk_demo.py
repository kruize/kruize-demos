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
import os
import copy
import csv
import getopt
import itertools
import json
import sys
import time
from datetime import datetime
from time import sleep
from contextlib import redirect_stdout
import threading
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
    def thread_print(*args, **kwargs):
        with open(log_file, "a") as log:
            print(*args, **kwargs, file=log)

    # Get the bulk job status using the job id returned by Bulk API
    thread_print("\n#######################################")
    thread_print("Querying job status in a loop")
    thread_print("#######################################\n")
    verbose="true"
    response = get_bulk_job_status(job_id, verbose)
    job_status_json = response.json()

    # Loop until job status is COMPLETED
    job_status = job_status_json['status']

    while job_status != "COMPLETED":
        response = get_bulk_job_status(job_id, verbose)
        job_status_json = response.json()
        thread_print(f"Experiments: processed / Total -  {job_status_json['processed_experiments']} / {job_status_json['total_experiments']}")
        job_status = job_status_json['status']
        if job_status == "FAILED":
            thread_print("\nBulk Job FAILED due to this error: ", job_status_json['notifications'])
            thread_print("Check job_status.json for the job status")
            break
        sleep(10)

    # Dump the job status json into a file
    with open('job_status.json', 'w') as f:
        json.dump(job_status_json, f, indent=4)

    if job_status == "COMPLETED":
        thread_print("\n#######################################")
        thread_print("Bulk Job Completed! Fetching the processed experiments and listing recommendations")
        thread_print("#######################################\n")

        exp_list = list(job_status_json["experiments"].keys())
        # List recommendations for the experiments for which recommendations are available
        recommendations_json_arr = []
        if exp_list != "":
            for exp_name in exp_list:
                response = list_recommendations(exp_name)
                reco = response.json()
                recommendations_json_arr.append(reco)

                # Dump the recommendations into a json file
                with open('recommendations_data.json', 'w') as f:
                    json.dump(recommendations_json_arr, f, indent=4)

            thread_print("Recommendations for all experiments are available in recommendations_data.json")
        else:
            thread_print("Something went wrong! There are no experiments with recommendations!")

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
    print("✅ Invoked job_id" , job_id)

    # Sleep for 10s initially to gather total experiments and failures
    time.sleep(10)

    verbose="true"
    response = get_bulk_job_status(job_id, verbose)
    job_status_json = response.json()
    total_experiments = job_status_json['total_experiments']
    job_status = job_status_json['status']
    if job_status == "FAILED":
        print("❌ Bulk Job FAILED due to this error: ", job_status_json['notifications'])
    else:
        thread = threading.Thread(target=bulk_status, args=(job_id,)) #, daemon=False)
        thread.start()
        print(f"🔔 Bulk job experiment details are currently being updated in {log_file}.")
        #print("🔔 You can check job_status.log for ongoing updates as experiments are processed.")
        print(f"🔄 Processing {total_experiments} experiments. Please wait...",end="")

        while thread.is_alive():
            print(".", end="")
            time.sleep(60)

        #print("\nJob status is available in job_status.log.")
        print("✅ Completed!")
        print("📌 Recommendations for all experiments can be found in recommendations_data.json.\n")


log_file = os.getenv("LOG_FILE", "kruize-bulk-demo.log")

if __name__ == '__main__':
    main(sys.argv[1:])
