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
    input_json_file = "input.json"

    json_data = json.load(open(input_json_file))

    experiment_name = json_data[0]['experiment_name']
    deployment_name = json_data[0]['deployment_name']
    namespace = json_data[0]['namespace']

    print("Experiment name = ", experiment_name)
    print("Deployment name = ", deployment_name)
    print("Namespace = ", namespace)

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

    # Create experiment using the specified json
    num_exps = 1
    for i in range(num_exps):
        create_experiment(input_json_file)

    # Post the experiment results
    recommendations_json_arr = []
    num_exps = 37
    for i in range(1, num_exps):
        json_file = "./json_files/result_" + str(i) + ".json"
        update_results(json_file)

        reco = list_recommendations(experiment_name, deployment_name, namespace)
        recommendations_json_arr.append(reco)

    # Dump the results & recommendations into json files
    with open('reco.json', 'w') as f:
        json.dump(recommendations_json_arr, f)

    list_exp_json = list_experiments()
    with open('list_exps.json', 'w') as f:
        json.dump(list_exp_json, f)



if __name__ == '__main__':
    main(sys.argv[1:])
