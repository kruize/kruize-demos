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

import copy
import csv
import getopt
import itertools
import json
import sys
import time
from datetime import datetime

from helpers.utils import create_json_from_csv
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
    create_exp_json_file = "./json_files/create_exp.json"
    find = []
    num_entries = 97

    json_data = json.load(open(create_exp_json_file))

    find.append(json_data[0]['experiment_name'])
    find.append(json_data[0]['kubernetes_objects'][0]['name'])
    find.append(json_data[0]['kubernetes_objects'][0]['namespace'])

    print(find)

    try:
        opts, args = getopt.getopt(argv, "h:c:d:")
    except getopt.GetoptError:
        print("demo.py -c <cluster type>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("demo.py -c <cluster type>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg
        elif opt == '-d' and arg is not None:
            num_entries = int(arg) * 96
            num_entries += 1

    print("demo.py -c %s" % (cluster_type))

    # Form the kruize url
    form_kruize_url(cluster_type)

    # Create the performance profile
    perf_profile_json_file = "./json_files/resource_optimization_openshift.json"
    create_performance_profile(perf_profile_json_file)

    recommendations_json_arr = []
    ## Create experiments from the experiments_list and use related csv data to updateResults
    experiments_list = ['eap-app_deploymentconfig_america', 'example_replicationcontroller_america',
                        'tfb-qrh_deployment_tfb-tests', 'rhsso-operator_deployment_sso']
    for exp in experiments_list:
        experiment_json = "./json_files/experiment_jsons/" + exp + ".json"
        experiment_csv = "./csv_data/" + exp + ".csv"
        create_experiment(experiment_json)
        json_data = json.load(open(experiment_json))
        experiment_name = json_data[0]['experiment_name']

        with open(experiment_csv, 'r') as csv_file:
            reader = csv.reader(csv_file)
            header = next(reader)

            limited_reader = itertools.islice(reader, num_entries)
            for row in limited_reader:
                if not any(row):
                    continue
                with open('intermediate.csv', mode='w', newline='') as outfile:
                    writer = csv.writer(outfile)
                    writer.writerow(header)
                    writer.writerow(row)

                # Convert the results csv to json
                resultsjson_file = "./json_files/experiment_jsons/results.json"
                create_json_from_csv("./intermediate.csv", resultsjson_file)
                update_results(resultsjson_file)

                reco = list_recommendations(experiment_name)
                recommendations_json_arr.append(reco)

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

        file_path = './resource_usage_metrics_data/result_%s_to_%s.json' % (current_index, batch_size)
        with open(file_path, 'w') as json_file:
            json.dump(batch, json_file)
        update_results(file_path)
        batch_deep_copy = copy.deepcopy(batch)
        for item in batch_deep_copy:
            item['interval_start_time'] = datetime.strptime(item['interval_start_time'], "%Y-%m-%dT%H:%M:%S.%fZ")
            item['interval_end_time'] = datetime.strptime(item['interval_end_time'], "%Y-%m-%dT%H:%M:%S.%fZ")
        max_time = max(batch_deep_copy, key=lambda x: x['interval_end_time'])['interval_end_time']
        update_recommendations(experiment_name, max_time.strftime("%Y-%m-%dT%H:%M:%S.%fZ")[:-4] + "Z")
        # Update the current index for the next batch
        current_index += batch_size
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
