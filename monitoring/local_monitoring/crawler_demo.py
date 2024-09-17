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

import copy
import csv
import getopt
import itertools
import json
import sys
import time
from datetime import datetime

from kruize.kruize import *


def generate_json(find_arr, json_file, filename, i):
    with open(json_file, 'r') as file:
        data = file.read()

    for find in find_arr:
        replace = find + "_" + str(i)
        data = data.replace(find, replace)

    with open(filename, 'w') as file:
        file.write(data)


def main(argv):
    cluster_type = "minikube"

    #json_data = json.load(open(crawler_json_file))
    #with open(filename, 'w') as file:
    #    file.write(data)

    try:
        opts, args = getopt.getopt(argv, "h:c:d:")
    except getopt.GetoptError:
        print("crawler_demo.py -c <cluster type>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("crawler_demo.py -c <cluster type>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg
        elif opt == '-d' and arg is not None:
            num_entries = int(arg) * 96
            num_entries += 1

    print("crawler_demo.py -c %s" % (cluster_type))

    # Form the kruize url
    form_kruize_url(cluster_type)

    # Create the metric profile
    metric_profile_json_file = "./resource_optimization_openshift.json"
    create_metric_profile(metric_profile_json_file)

    # Invoke the crawler service with the specified json
    crawler_json_file = "./crawler_input.json"
    response = crawler(crawler_json_file)

    # Obtain the job id from the response from crawler service
    job_id_json = response.json()

    print(job_id_json)
    job_id = job_id_json['jobID']
    print(job_id)

    # Get the crawler job status using the job id
    response = get_crawler_job_status(job_id)
    job_status_json = response.json()

    # Loop until job status is COMPLETED
    job_status = job_status_json['status']
   # while job_status != "COMPLETED":
    #    job_status = job_status_json['status']

    print(job_status)

    # Fetch the list of experiments for which recommendations are available
    exp_list = job_status_json['data']['recommendations']['data']['completed']
    print(exp_list)

    # List recommendations for the experiments for which recommendations are available
    recommendations_json_arr = []

    if exp_list != "":
        for exp_name in exp_list:
            reco = list_recommendations(exp_name)
            recommendations_json_arr.append(reco)

        # Dump the recommendations into json files
        with open('recommendations_data.json', 'w') as f:
            json.dump(recommendations_json_arr, f, indent=4)

if __name__ == '__main__':
    main(sys.argv[1:])
