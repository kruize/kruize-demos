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

import sys, getopt
import json
import os
import time
import csv
import itertools

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from recommendations_demo.kruize.kruize import *
from recommendations_demo import recommendation_validation

def match_experiments(listexperimentsjson,inputcsv):
    with open(listexperimentsjson, 'r') as jsonfile:
        data = json.load(jsonfile)
    experiments = 0
    counter = 0
    if not data:
            print("No experiments found!")
    else:
            with  open(inputcsv, 'r') as csvfile:
                reader = csv.DictReader(csvfile)
                for row in reader:
                    for key, value in data.items():
                        if "experiment_name" in value:
                           experiment_name = value["experiment_name"]
                           experiments += 1
                   # Assuming single kubernetes object
                        if "kubernetes_objects" in value:
                           kobj = value["kubernetes_objects"][0]
                           containerNames=[]
                           k8ObjectName = ""
                           namespace = ""
                           k8ObjectType = ""
                           for k,v in kobj.items():
                               if "name" in k:
                                  k8ObjectName = kobj["name"]
                               if "namespace" in k:
                                  namespace = kobj["namespace"]
                               if "type" in k:
                                  k8ObjectType = kobj["type"]
                               if "containers" in k:
                                  for container in kobj["containers"].values():
                                      containerName = container["container_name"]
                                      containerNames.append(containerName)
                           print("Experiment details from experiment.json : name= ",k8ObjectName,"; Type= ",k8ObjectType," ; Container= ",containerNames, "Namespace=", namespace)
                           
                           if row["k8_object_name"] == k8ObjectName and row["namespace"] == namespace and row["k8_object_type"].lower() == k8ObjectType.lower():
                               if row["container_name"] in containerNames:
                                   print("The experiment exists with the same name, type, namespace and container")
                                   break
                               else:
                                   print("The experiment exists with the same name, type, namespace. Container is different.")
                                   break
                           elif row["k8_object_name"] == k8ObjectName:
                               print("The experiment exists with the same name.But, type and namespace might be different.")
                               break
                           else:
                               counter += 1
                               continue
                           
                           print("Experiment details from results : name= ",row["k8_object_name"],"; Type= ",row["k8_object_type"]," ; Container= ",row["container_name"], "Namespace=", row["namespace"])
            if experiments == counter:
               print("The experiment is not matching with any existing ones.")

def create_expjson(clustername,filename):
#cluster,experiment_name,k8objname,k8objtype,namespace,container_image,container_name):
    with open("./recommendations_demo/json_files/create_exp_template.json", 'r') as jsonfile:
        data = json.load(jsonfile)

    with open(filename, 'r') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            ## Hardcoding for tfb-results and demo benchmark. Updating them only if these columns are not available.
            ## Keep this until the metrics queries are fixed in benchmark to get the below column data
            columns_tocheck = [ "image_name" , "container_name" , "k8_object_type" , "k8_object_name" , "namespace" ]
            for col in columns_tocheck:
                if col not in row:
                    row["image_name"] = "kruize/tfb-qrh:2.9.1.F"
                    row["container_name"] = "tfb-server"
                    row["k8_object_type"] = "deployment"
                    row["k8_object_name"] = "tfb-qrh-sample-0"
                    row["namespace"] = "tfb-perf"
                    row["cluster_name"] = "e23-alias"

            replacements = {
                    "EXP_NAME": row["k8_object_name"] + '|' + row["k8_object_type"] + '|' + row["namespace"],
                    "CLUSTER_NAME": row["cluster_name"],
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
        limited_reader = itertools.islice(reader, 97)
        for row in limited_reader:
        #for row in reader:
            recommendations_json_arr = []
            if not any(row):
                continue
            with open('intermediate.csv', mode='w', newline='') as outfile:
                writer = csv.writer(outfile)
                writer.writerow(header)
                writer.writerow(row)
         
            # Commenting this for now to make run faster
            # TODO : Check if experiment exists  and update Results. Else createExp
            #print("\nGet list experiments before starting to update results")
            #list_exp_json = list_experiments()
            #with open('list_experiments_data.json', 'w') as f:
            #   json.dump(list_exp_json, f, indent=4)
            #print("\nMatch if any experiment exists with the current row data.")
            #match_experiments("list_experiments_data.json","intermediate.csv")


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

            # Commenting out sleep
            #time.sleep(1)
            #print("\nGenerating the recommendations...")
            #reco = list_recommendations(experiment_name)
            #recommendations_json_arr.append(reco)

            # Dump the results & recommendations into json files
            #with open('recommendations_data.json', 'w') as f:
            #   json.dump(recommendations_json_arr, f, indent=4)
            #recommendation_validation.update_recomm_csv("recommendations_data.json")

    return


def getMetricsWithRecommendations(cluster_type,experiment_name):
    form_kruize_url(cluster_type)
    list_metricsrec_json = list_metrics_with_recommendations(experiment_name)
    with open('metrics_recommendations_data.json', 'w') as f:
            json.dump(list_metricsrec_json, f, indent=4)
    return 

def getExperimentNames(cluster_type):
    experiment_names = []
    form_kruize_url(cluster_type)
    list_experiments_json = list_experiments()
    for obj in list_experiments_json:
        name = obj.get('experiment_name');
        if name:
            experiment_names.append(name)
    print(experiment_names)
    return experiment_names

def getRecommendations(cluster_type,experiment_name):
    form_kruize_url(cluster_type)
    recommendations_json = list_recommendations(experiment_name)
    with open('experiment_recommendations_data.json', 'w') as f:
            json.dump(recommendations_json, f, indent=4)
    return

def listClusters(cluster_type):
    form_kruize_url(cluster_type)
    list_clusters_data = list_clusters()
    return list_clusters_data

def summarizeClusterData(cluster_type, cluster_name=None, namespace_name=None):
    form_kruize_url(cluster_type)
    recommendation_validation.create_cluster_data_csv('cluster','clusterData.csv')
    cluster_data_json = summarize_cluster_data(cluster_name,namespace_name)
    with open('cluster_data.json', 'w') as f:
            json.dump(cluster_data_json, f, indent=4)
    return

def summarizeNamespaceData(cluster_type, namespace_name=None):
    form_kruize_url(cluster_type)
    recommendation_validation.create_cluster_data_csv('clusterNamespace','namespaceData.csv')
    namespace_data_json = summarize_namespace_data(namespace_name)
    with open('namespace_data.json', 'w') as f:
            json.dump(namespace_data_json, f, indent=4)
    return

## Temporary function to get list of clusters and parse individually as /summarize has issues.
def summarizeAllData(cluster_type):
    form_kruize_url(cluster_type)
    list_clusters_data = list_clusters()
    recommendation_validation.create_cluster_data_csv('cluster','clusterData.csv')
    recommendation_validation.create_cluster_data_csv('clusterNamespace','clusterNamespaceData.csv')
    for cluster in list_clusters_data:
        print(cluster)
        cluster_data_json = summarize_cluster_data(cluster)
        with open('cluster_data.json', 'w') as f:
            json.dump(cluster_data_json, f, indent=4)
        recommendation_validation.get_cluster_data_csv('cluster','cluster_data.json','clusterData.csv')
        #print(cluster_data_json)
        first_cluster_summary = cluster_data_json[0].get('summary', {})
        namespaces = first_cluster_summary.get('namespaces', {}).get('names', [])
        for namespace in namespaces:
            print(namespace)
            cluster_namespace_data_json = summarize_cluster_data(cluster,namespace)
            print(cluster_namespace_data_json)
            with open('cluster_namespace_data.json', 'w') as f:
                json.dump(cluster_namespace_data_json, f, indent=4)
            recommendation_validation.get_cluster_data_csv('clusterNamespace','cluster_namespace_data.json','clusterNamespaceData.csv')

def getAllExperimentsRecommendations(cluster_type):
    form_kruize_url(cluster_type)
    exp_names = getExperimentNames(cluster_type)
    for name in exp_names:
        recommendation_json = list_recommendations(name)
        with open('exp_recommendation_data.json', 'w') as f:
            json.dump(recommendation_json, f, indent=4)
        recommendation_validation.get_recommondations('exp_recommendation_data.json')


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

    # Hardcoding the clustername as the details aren't available
    clustername = "e23-alias"

    print("Cluster type = ", cluster_type)

    # Form the kruize url
    form_kruize_url(cluster_type)

    # Create the performance profile
    #perf_profile_json_file = "./json_files/resource_optimization_openshift.json"
    create_performance_profile(perf_profile_json_file)

    # Create and updateResults
    createExpAndupdateResults(clustername,resultscsv)

if __name__ == '__main__':
    main(sys.argv[1:])
