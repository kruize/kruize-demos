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
import csv

def main(argv):
    cluster_type = "minikube"

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
#    perf_profile_json_file = "./json_files/resource_optimization_openshift.json"
    create_performance_profile(perf_profile_json_file)

    # Create experiments using the specified json
#    tmp_create_exp_json_file = "./json_files/create_exp.json"
    create_experiment(tmp_create_exp_json_file)

    json_data = json.load(open(tmp_create_exp_json_file))
    experiment_name = json_data[0]['experiment_name']
    deployment_name = json_data[0]['kubernetes_objects'][0]['name']
    namespace = json_data[0]['kubernetes_objects'][0]['namespace']

    print("Experiment name = ", experiment_name)
    print("Deployment name = ", deployment_name)
    print("Namespace = ", namespace)

    # Post the experiment results
    recommendations_json_arr = []

    print("\n*************************************************************************************")
    print("Updating results for one of the experiments and fetching recommendations from Kruize...")
    print("*************************************************************************************\n")

    # Create json using each row of a csv and update results
    #python3 ${SCRIPTS_REPO}/csv2json.py $file ${SCRIPTS_REPO}/results/results.json
    with open(resultscsv, newline='') as csvfile:    
        reader = csv.reader(csvfile)    
        header = next(reader)    
        for row in reader:
            if not any(row):
                continue        
            with open('intermediate.csv', mode='w', newline='') as outfile:
                writer = csv.writer(outfile)
                writer.writerow(header)
                writer.writerow(row)
                #${SCRIPTS_REPO}/csv2json.py $file ${SCRIPTS_REPO}/results/results.json
            try:
                subprocess.run(['python3', './recommendations_demo/csv2json.py', './intermediate.csv', './recommendations_demo/results/results.json'])
            except subprocess.CalledProcessError as e:
                output = e.output
                
            json_file = "./recommendations_demo/results/results.json"
            update_results(json_file)
            
            # Sleep
            time.sleep(40)

    reco = list_recommendations(experiment_name)
    recommendations_json_arr.append(reco)

    # Dump the results & recommendations into json files
    with open('recommendations_data.json', 'w') as f:
        json.dump(recommendations_json_arr, f, indent=4)

    list_exp_json = list_experiments()
    with open('usage_data.json', 'w') as f:
        json.dump(list_exp_json, f, indent=4)

perf_profile_json_file = sys.argv[1]
tmp_create_exp_json_file = sys.argv[2]
resultscsv = sys.argv[3]

if __name__ == '__main__':
    main(sys.argv[1:])
