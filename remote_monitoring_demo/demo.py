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
        opts, args = getopt.getopt(argv,"h:c:")
    except getopt.GetoptError:
        print("demo.py -c <cluster type>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("demo.py -c <cluster type>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg

    print("Cluster type = ", cluster_type)

    # Form the kruize url
    form_kruize_url(cluster_type)

    # Create the performance profile
    perf_profile_json_file = "./json_files/resource_optimization_openshift.json"
    create_performance_profile(perf_profile_json_file)

    recommendations_json_arr = []
    ## Create experiments from the experiments_list and use related csv data to updateResults
    experiments_list = ['eap-app_deploymentconfig_america', 'example_replicationcontroller_america', 'tfb-qrh_deployment_tfb-tests', 'rhsso-operator_deployment_sso']
    for exp in experiments_list:
        experiment_json = "./json_files/experiment_jsons/" + exp + ".json"
        experiment_csv = "./csv_data/" + exp + ".csv"
        create_experiment(experiment_json)
        json_data = json.load(open(experiment_json))
        experiment_name = json_data[0]['experiment_name']

        with open(experiment_csv, 'r') as csv_file:
            reader = csv.reader(csv_file)
            header = next(reader)
            for row in reader:
                #if not any(row):
                #    continue
                with open('intermediate.csv', mode='w', newline='') as outfile:
                    writer = csv.writer(outfile)
                    writer.writerow(header)
                    writer.writerow(row)
                    
                # Convert the results csv to json
                resultsjson_file = "./json_files/experiment_jsons/results.json"
                create_json_from_csv("./intermediate.csv",resultsjson_file)
                update_results(resultsjson_file)
                
                # Sleep
                #time.sleep(1)
                
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

    for i in range(1, num_exp_res):
        json_file = "./resource_usage_metrics_data/result_" + str(i) + ".json"
        update_results(json_file)

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
