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
#from recommendations_demo.
import recommendation_validation
import sys, getopt
import json
import os
import time
import csv

def match_experiments(listexperimentsjson,inputcsv):
    with open(listexperimentsjson, 'r') as jsonfile:
        data = json.load(jsonfile)
       
    if not data:
        print("No experiments found!")
    else:
        for key, value in data.items():
            if "experiment_name" in value:
                experiment_name = value["experiment_name"]
            if "deployments" in value:
                for k,v in value["deployments"].items():
                    if "name" in v:
                        k8ObjectName = v["name"]
                    if "namespace" in v:
                        namespace = v["namespace"]
                    if "type" in v:
                        k8ObjectType = v["type"]
                    if "containers" in v:
                        for k1,v1 in v["containers"].items():
                            if "container_name" in v1:
                                containerName = v1["container_name"]
                                
            with open(inputcsv, 'r') as csvfile:
                reader = csv.DictReader(csvfile)
                for row in reader:
                    #print(row)
                    if row["k8_object_name"] == k8ObjectName and row["namespace"] == namespace and row["k8_object_type"].lower() == k8ObjectType.lower() and row["container_name"] == containerName:
                        print("The experiment exists with the same name, type, namespace and container")
                    elif row["k8_object_name"] == k8ObjectName and row["namespace"] == namespace and row["k8_object_type"].lower() == k8ObjectType.lower():
                        print("The experiment exists with the same name, type, namespace. Container is different.")
                    elif row["k8_object_name"] == k8ObjectName and row["namespace"] == namespace and row["container_name"] == containerName:
                        print("The experiment exists with the same name, namespace and container. But the type is different")
                    elif row["k8_object_name"] == k8ObjectName and row["k8_object_type"].lower() == k8ObjectType.lower() and row["container_name"] == containerName:
                        print("The experiment exists with the same name, type, container. But on a different namespace")
                    elif row["k8_object_name"] == k8ObjectName:
                        print("The experiment exists with the same name")
                    else:
                        print("The experiment is not matching with any existing ones")
                    print("Experiment details from experiment.json : name= ",k8ObjectName,"; Type= ",k8ObjectType," ; Container= ",containerName, "Namespace=", namespace)
                    print("Experiment details from results : name= ",row["k8_object_name"],"; Type= ",row["k8_object_type"]," ; Container= ",row["container_name"], "Namespace=", row["namespace"]) 



def create_expjson(clustername,filename):
#cluster,experiment_name,k8objname,k8objtype,namespace,container_image,container_name):
    with open("./recommendations_demo/json_files/create_exp_template.json", 'r') as jsonfile:
        data = json.load(jsonfile)

    with open(filename, 'r') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            replacements = {
                    "EXP_NAME": row["k8_object_name"],
                    "CLUSTER_NAME": clustername,
                    "k8Object_TYPE": row["k8_object_type"],
                    "k8Object_NAME": row["k8_object_name"],
                    "k8ObjectNAMESPACE": row["namespace"],
                    "k8Object_CONTAINER_IMAGE": row["image_name"],
                    "k8Object_CONTAINER_NAME": row["container_name"]
            }

    # Perform replacements
    for key, value in replacements.items():
        for obj in data:
            json_str = json.dumps(obj)
            json_str = json_str.replace(key, value)
            obj.update(json.loads(json_str))

    newdata = json.dumps(data)
    with open("./recommendations_demo/json_files/create_exp.json", 'w') as file:
        file.write(newdata)


def createExpAndupdateResults(clustername,resultscsv):
    # Create json using each row of a csv and update results
    with open(resultscsv, newline='') as csvfile:
        reader = csv.reader(csvfile)
        header = next(reader)
        for row in reader:
            recommendations_json_arr = []
            if not any(row):
                continue
            with open('intermediate.csv', mode='w', newline='') as outfile:
                writer = csv.writer(outfile)
                writer.writerow(header)
                writer.writerow(row)
          
            # TODO : Check if experiment exists  and update Results. Else createExp
            print("\nGet list experiments before starting to update results")
            list_exp_json = list_experiments()
            with open('list_experiments_data.json', 'w') as f:
               json.dump(list_exp_json, f, indent=4)
            print("\nMatch if any experiment exists with the current row data.")
            match_experiments("list_experiments_data.json","intermediate.csv")


            ## Assuming there is one container for a template.
            # Create Experiment json for that row.
            print("\nCreating the experiment...")
            create_expjson(clustername,"intermediate.csv")
            create_experiment("./recommendations_demo/json_files/create_exp.json")

            json_data = json.load(open("./recommendations_demo/json_files/create_exp.json"))
            experiment_name = json_data[0]['experiment_name']
            k8ObjectName = json_data[0]['kubernetes_objects'][0]['name']
            k8ObjectType = json_data[0]['kubernetes_objects'][0]['type']
            namespace = json_data[0]['kubernetes_objects'][0]['namespace']
            
            print("Experiment_name = ", experiment_name, " K8_Object_name = ", k8ObjectName, " K8_Object_type = ",k8ObjectType, " Namespace = ", namespace)

            # Convert the results csv to json
            print("\nConvert the results csv to json...")
            recommendation_validation.create_json_from_csv("./intermediate.csv","./recommendations_demo/results/results.json")

            json_file = "./recommendations_demo/results/results.json"
            print("\nUpdating the results to Kruize API...")
            update_results(json_file)

            # Sleep
            time.sleep(40)
            print("\nGenerating the recommendations...")
            reco = list_recommendations(experiment_name)
            recommendations_json_arr.append(reco)

            # Dump the results & recommendations into json files
            with open('recommendations_data.json', 'w') as f:
               json.dump(recommendations_json_arr, f, indent=4)
                
            recommendation_validation.update_recomm_csv("recommendations_data.json")

        print("\nPrint the list of experiments after updating.")
        list_exp_json = list_experiments()
        with open('usage_data.json', 'w') as f:
            json.dump(list_exp_json, f, indent=4)




def main(argv):
    try:
        opts, args = getopt.getopt(argv,"h:c:p:e:r:")
    except getopt.GetoptError:
        print("demo.py -c <cluster type>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("demo.py -c <cluster type>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg
        elif opt == '-p':
            perf_profile_json_file = arg
        elif opt == '-e':
            tmp_create_exp_json_file = arg
        elif opt == '-r':
            resultscsv = arg
    # Default duration to 6 hours if not passed.
    if '-r' not in sys.argv:
        resultscsv = 'metrics.csv'

    clustername = "e23-alias"

    #print("Resultscsv = ", resultscsv)
    print("Cluster type = ", cluster_type)

    # Form the kruize url
    form_kruize_url(cluster_type)

    # Create the performance profile
#    perf_profile_json_file = "./json_files/resource_optimization_openshift.json"
    create_performance_profile(perf_profile_json_file)

    # Create and updateResults
    createExpAndupdateResults(clustername,resultscsv)

if __name__ == '__main__':
    main(sys.argv[1:])
