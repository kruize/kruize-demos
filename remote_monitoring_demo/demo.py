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
import sys, getopt
import json
import os
import time

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
    create_exp_json_file = "create_exp.json"
    find = []

    json_data = json.load(open(create_exp_json_file))

    find.append(json_data[0]['experiment_name'])
    find.append(json_data[0]['deployment_name'])
    find.append(json_data[0]['namespace'])

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

    # Create experiments using the specified json
    num_exps = 10
    for i in range(num_exps):
        tmp_create_exp_json_file = "/tmp/create_exp.json"
        generate_json(find, create_exp_json_file, tmp_create_exp_json_file, i)
        create_experiment(tmp_create_exp_json_file)

        if i == 0:
            json_data = json.load(open(create_exp_json_file))

            experiment_name = json_data[0]['experiment_name']
            deployment_name = json_data[0]['deployment_name']
            namespace = json_data[0]['namespace']

            print("Experiment name = ", experiment_name)
            print("Deployment name = ", deployment_name)
            print("Namespace = ", namespace)

    # Post the experiment results
    recommendations_json_arr = []
    num_exp_res = 37
    for i in range(1, num_exp_res):
        json_file = "./resource_usage_metrics_data/result_" + str(i) + ".json"
        update_results(json_file)

        # Sleep 

        reco = list_recommendations(experiment_name, deployment_name, namespace)
        recommendations_json_arr.append(reco)

    # Dump the results & recommendations into json files
    with open('recommendations.json', 'w') as f:
        json.dump(recommendations_json_arr, f)

    list_exp_json = list_experiments()
    with open('experiments_data.json', 'w') as f:
        json.dump(list_exp_json, f)


if __name__ == '__main__':
    main(sys.argv[1:])
