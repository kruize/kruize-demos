"""
Copyright (c) 2022, 2022 Red Hat, IBM Corporation and others.

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

from kruize.kruize import *
from helpers.utils import create_json_from_csv
import sys, getopt
import json
import os
import time
import csv
import itertools

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
    create_exp_json_file = "./json_files/create_exp.json"
    find = []

    json_data = json.load(open(create_exp_json_file))

    find.append(json_data[0]['experiment_name'])
    find.append(json_data[0]['kubernetes_objects'][0]['name'])
    find.append(json_data[0]['kubernetes_objects'][0]['namespace'])

    print(find)

    try:
        opts, args = getopt.getopt(argv,"h:c:b:")
    except getopt.GetoptError:
        print("demo.py -c <cluster type>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("demo.py -c <cluster type>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg

    print("demo.py -c %s"%(cluster_type))

    # Form the kruize url
    form_kruize_url(cluster_type)

    # Create the performance profile
    perf_profile_json_file = "./json_files/resource_optimization_openshift.json"
    create_performance_profile(perf_profile_json_file)

    # Create experiments using the specified json
    num_exps = 1
    for i in range(num_exps):
        tmp_create_exp_json_file = "/tmp/create_exp.json"
        generate_json(find, create_exp_json_file, tmp_create_exp_json_file, i)
        create_experiment(tmp_create_exp_json_file)

        if i == 0:
            json_data = json.load(open(tmp_create_exp_json_file))

            experiment_name = json_data[0]['experiment_name']
            deployment_name = json_data[0]['kubernetes_objects'][0]['name']
            namespace = json_data[0]['kubernetes_objects'][0]['namespace']

            print("Experiment name = ", experiment_name)
            print("Deployment name = ", deployment_name)
            print("Namespace = ", namespace)

    # Post the experiment results
    recommendations_json_arr = []
    num_exp_res = 151

    print("\n*************************************************************************************")
    print("Updating results for one of the experiments and fetching recommendations from Kruize...")
    print("*************************************************************************************\n")

    bulk_payload = []
    for i in range(1, num_exp_res):
        json_file_path = "./resource_usage_metrics_data/result_" + str(i) + ".json"
        with open(json_file_path, 'r') as json_file:
            json_data = json_file.read()
        json_parsed = json.loads(json_data)
        bulk_payload.append(json_parsed[0])

    # Define the batch size
    batch_size = 100

    # Loop to fetch elements in batches
    current_index = 0
    while current_index < len(bulk_payload):
        # Get the current batch
        batch = bulk_payload[current_index:current_index + batch_size]

        file_path = './resource_usage_metrics_data/result_%s_to_%s.json'%(current_index,batch_size)
        with open(file_path, 'w') as json_file:
            json.dump(batch, json_file)
        update_results(file_path)

        # Update the current index for the next batch
        current_index += batch_size
    end_dates = [
        "2023-04-02T00:45:00.000Z",
        "2023-04-02T01:15:00.421Z",
        "2023-04-02T01:30:00.433Z",
        "2023-04-02T01:45:00.000Z",
        "2023-04-02T02:00:00.000Z",
        "2023-04-02T02:15:00.000Z",
        "2023-04-02T02:30:00.000Z",
        "2023-04-02T02:45:00.000Z",
        "2023-04-02T03:00:00.000Z",
        "2023-04-02T03:15:00.000Z",
        "2023-04-02T03:45:00.000Z",
        "2023-04-02T04:00:00.000Z",
        "2023-04-02T04:15:00.000Z",
        "2023-04-02T04:30:00.000Z",
        "2023-04-02T04:45:00.000Z",
        "2023-04-02T05:00:00.000Z",
        "2023-04-02T05:15:00.000Z",
        "2023-04-02T05:30:00.000Z",
        "2023-04-02T05:45:00.000Z",
        "2023-04-02T06:00:00.000Z",
        "2023-04-02T06:15:00.000Z",
        "2023-04-02T06:30:00.000Z",
        "2023-04-02T07:00:00.000Z",
        "2023-04-02T07:15:00.000Z",
        "2023-04-02T07:30:00.000Z",
        "2023-04-02T07:45:00.000Z",
        "2023-04-02T08:00:00.000Z",
        "2023-04-02T08:15:00.000Z",
        "2023-04-02T08:30:00.000Z",
        "2023-04-02T08:45:00.000Z",
        "2023-04-02T09:00:00.000Z",
        "2023-04-02T09:15:00.000Z",
        "2023-04-02T09:30:00.000Z",
        "2023-04-02T09:45:00.000Z",
        "2023-04-02T10:00:00.000Z",
        "2023-04-02T10:15:00.000Z",
        "2023-04-02T10:30:00.000Z",
        "2023-04-02T10:45:00.000Z",
        "2023-04-02T11:00:00.770Z",
        "2023-04-02T11:15:00.770Z",
        "2023-04-02T11:30:00.770Z",
        "2023-04-02T11:45:00.770Z",
        "2023-04-02T12:00:00.770Z",
        "2023-04-02T12:15:00.770Z",
        "2023-04-02T12:30:00.770Z",
        "2023-04-02T12:45:00.770Z",
        "2023-04-02T13:00:00.110Z",
        "2023-04-02T13:15:00.350Z",
        "2023-04-02T13:30:00.680Z"
    ]
    for enddate in end_dates:
        update_recommendations(experiment_name,enddate)
    # Sleep
    time.sleep(1)
    reco = list_recommendations(experiment_name)
    recommendations_json_arr.append(reco)

    # Dump the results & recommendations into json files
    with open('recommendations_data.json', 'w') as f:
        json.dump(recommendations_json_arr, f, indent=4)

    list_exp_json = list_experiments()
    with open('usage_data.json', 'w') as f:
        json.dump(list_exp_json, f, indent=4)


if __name__ == '__main__':
    main(sys.argv[1:])
