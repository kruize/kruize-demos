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
    result_json_file = "result.json"
    input_json_file = "input.json"
    find = []
    json_data = json.load(open(input_json_file))

    find.append(json_data[0]['experiment_name'])
    find.append(json_data[0]['deployment_name'])
    find.append(json_data[0]['namespace'])

    print("Experiment name = ", json_data[0]['experiment_name'])
    print("Deployment name = ", json_data[0]['deployment_name'])
    print("Namespace = ", json_data[0]['namespace'])


    try:
        opts, args = getopt.getopt(argv,"hi:r:n:c:")
    except getopt.GetoptError:
        print("demo.py -c <cluster type> -n <no. of experiments> -i <input json> -r <result json>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("demo.py -c <cluster type> -n <no. of experiments> -i <input json> -r <result json>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg
        elif opt == '-n':
            num_exps = int(arg)
        elif opt == '-i':
            input_json_file = arg
        elif opt == '-r':
            result_json_file = arg

    print("Cluster type = ", cluster_type)

    # Form the kruize url
    form_kruize_url(cluster_type)

    # Create experiment using the specified json
    num_exps = 1
    for i in range(num_exps):
        json_file = "./input.json"
        #json_file = "/tmp/input.json"
        #generate_json(find, input_json_file, json_file, i)
        create_experiment(json_file)

    # Post the experiment results
    recommendations_json_arr = []
    num_exps = 37
    for i in range(1, num_exps):
        #json_file = "/tmp/result.json"
        json_file = "./json_files/result_" + str(i) + ".json"
        print(json_file)
        #generate_json(find, result_json_file, json_file, i)
        update_results(json_file)
    
        experiment_name = find[0]
        deployment_name = find[1]
        namespace = find[2]
        reco = list_recommendations(experiment_name, deployment_name, namespace)

        combined_json = combine_jsons(json_file, reco)
        recommendations_json_arr.append(combined_json)

    # Dump the combined jsons containing results & recommendations into a json file
    with open('combined_data.json', 'w') as f:
        json.dump(recommendations_json_arr, f)

if __name__ == '__main__':
    main(sys.argv[1:])
