"""
Copyright (c) 2023, 2023 Red Hat, IBM Corporation and others.

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
import pandas as pd
import shutil
from datetime import datetime

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

def create_expjson(filename):
    with open("./recommendations_demo/json_files/create_exp_template.json", 'r') as jsonfile:
        data = json.load(jsonfile)

    with open(filename, 'r') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            ## Hardcoding for tfb-results and demo benchmark. Updating them only if these columns are not available.
            ## Keep this until the metrics queries are fixed in benchmark to get the below column data
            columns_tocheck = [ "image_name" , "container_name" , "k8_object_type" , "k8_object_name" , "namespace" , "cluster_name" ]
            image_name = "kruize/tfb-qrh:2.9.1.F"
            container_name = "tfb-server"
            k8_object_type = "deployment"
            k8_object_name = "tfb-qrh-sample-0"
            namespace = "tfb-perf"
            cluster_name = "e23-alias"
	
            for col in columns_tocheck:
                if col not in row:
                    if col == "image_name":
                        row[col] = image_name
                    elif col == "container_name":
                        row[col] = container_name
                    elif col == "k8_object_type":
                        row[col] = k8_object_type
                    elif col == "k8_object_name":
                        row[col] = k8_object_name
                    elif col == "namespace":
                        row[col] = namespace
                    elif col == "cluster_name":
                        row[col] = cluster_name

            replacements = {
                    "EXP_NAME": row["container_name"] + '|' + row["k8_object_name"] + '|' + row["k8_object_type"] + '|' + row["namespace"] + '|' + row["cluster_name"],
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

def createExpAndupdateResults(resultscsv,days=None,bulk=None):
    if days is not None:
        num_entries = int(days) * 96
        num_entries += 1
    if bulk == "1":
        df = pd.read_csv(resultscsv)
        sort_columns = ['namespace', 'k8_object_type', 'k8_object_name', 'container_name']
        sorted_df = df.sort_values(sort_columns)
        grouped = sorted_df.groupby(sort_columns)
        temp_dir = 'temp'
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

        if not os.path.exists(temp_dir):
            os.makedirs(temp_dir)
        counter = 0
        for key, group in grouped:
            counter += 1
            filename = f"file_{counter}.csv"
            filepath = os.path.join(temp_dir, filename)
            group.to_csv(filepath, index=False)
            
        header_row = df.columns.tolist()
        new_df = pd.DataFrame(columns=header_row)
        for filename in os.listdir(temp_dir):
            if filename.endswith('.csv'):
                filepath = os.path.join(temp_dir, filename)
                df = pd.read_csv(filepath)
                with open(filepath, 'r') as input_csv:
                    csv_reader = csv.reader(input_csv)
                    header = next(csv_reader)
                    for row in csv_reader:
                        with open('intermediate.csv', mode='w', newline='') as outfile:
                            writer = csv.writer(outfile)
                            writer.writerow(header)
                            writer.writerow(row)
                            break
                print("\nCreating the experiment...")
                create_expjson("intermediate.csv")
                create_experiment("./recommendations_demo/json_files/create_exp.json")
                json_data = json.load(open("./recommendations_demo/json_files/create_exp.json"))
                experiment_name = json_data[0]['experiment_name']
                k8ObjectName = json_data[0]['kubernetes_objects'][0]['name']
                k8ObjectType = json_data[0]['kubernetes_objects'][0]['type']
                namespace = json_data[0]['kubernetes_objects'][0]['namespace']
                print("Experiment_name = ", experiment_name, " K8_Object_name = ", k8ObjectName, " K8_Object_type = ",k8ObjectType, " Namespace = ", namespace)
               
                # Split the csv's into multiples as updateResults doesn't support greater than 100 results.
                max_lines_per_csv = 100
                df = pd.read_csv(filepath)
                bulksplit_directory = 'bulksplitfiles/'
                os.makedirs(bulksplit_directory, exist_ok=True)
                num_output_files = (len(df) + max_lines_per_csv - 1) // max_lines_per_csv
                for i in range(num_output_files):
                    start_idx = i * max_lines_per_csv
                    end_idx = min((i + 1) * max_lines_per_csv, len(df))  # Ensure the last file includes remaining rows
                    split_df = df.iloc[start_idx:end_idx]
                    split_df.to_csv(f'{bulksplit_directory}output_{i + 1}.csv', index=False)

                    
                for filename1 in os.listdir(bulksplit_directory):
                    if os.path.isfile(os.path.join(bulksplit_directory, filename1)):
                        filepath1 = os.path.join(bulksplit_directory, filename1)
                        # Convert the results csv to json
                        print("\nConvert the results csv to json...")
                        recommendation_validation.create_json_from_csv(filepath1,"./recommendations_demo/results/results.json")
                        json_file = "./recommendations_demo/results/results.json"
                        print("\nUpdating the results to Kruize API...")
                        update_results(json_file)
                        #update_recommendations(experiment_name)
                        resultsjson = json.load(open(json_file))
                        for item in resultsjson:
                            item['interval_start_time'] = datetime.strptime(item['interval_start_time'],"%Y-%m-%dT%H:%M:%S.%fZ")
                            item['interval_end_time'] = datetime.strptime(item['interval_end_time'], "%Y-%m-%dT%H:%M:%S.%fZ")
                            update_recommendations(experiment_name, item['interval_end_time'].strftime("%Y-%m-%dT%H:%M:%S.%fZ")[:-4] + "Z")
                        #max_time = max(resultsjson, key=lambda x: x['interval_end_time'])['interval_end_time']
                        #update_recommendations(experiment_name, max_time.strftime("%Y-%m-%dT%H:%M:%S.%fZ")[:-4] + "Z")
                if os.path.exists(bulksplit_directory) and os.path.isdir(bulksplit_directory):
                    shutil.rmtree(bulksplit_directory)
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
    else:
        # Create json using each row of a csv and update results
        with open(resultscsv, newline='') as csvfile:
            reader = csv.reader(csvfile)
            header = next(reader)
            if days is not None:
                reader = itertools.islice(reader, num_entries)
            for row in reader:
                recommendations_json_arr = []
                if not any(row):
                    continue
                with open('intermediate.csv', mode='w', newline='') as outfile:
                    writer = csv.writer(outfile)
                    writer.writerow(header)
                    writer.writerow(row)         
                ## Assuming there is one container for a template.
                # Create Experiment json for that row.
                print("\nCreating the experiment...")
                create_expjson("intermediate.csv")
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
                #update_recommendations(experiment_name) 
                resultsjson = json.load(open(json_file))
                for item in resultsjson:
                    item['interval_start_time'] = datetime.strptime(item['interval_start_time'],"%Y-%m-%dT%H:%M:%S.%fZ")
                    item['interval_end_time'] = datetime.strptime(item['interval_end_time'], "%Y-%m-%dT%H:%M:%S.%fZ")
                max_time = max(resultsjson, key=lambda x: x['interval_end_time'])['interval_end_time']
                update_recommendations(experiment_name, max_time.strftime("%Y-%m-%dT%H:%M:%S.%fZ")[:-4] + "Z")
                
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
        namespaces = cluster_data_json[0].get('namespaces', {}).get('names', [])
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
        opts, args = getopt.getopt(argv,"h:c:p:e:r:b:d:")
    except getopt.GetoptError:
        print("recommendation_experiment.py -c <cluster type>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("recommendation_experiment.py -c <cluster type>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg
        elif opt == '-p':
            perf_profile_json_file = arg
        elif opt == '-e':
            tmp_create_exp_json_file = arg
        elif opt == '-r':
            resultscsv = arg
        elif opt == '-b':
            bulk_results = arg
        elif opt == '-d':
            days_data = arg
    
    if '-r' not in sys.argv:
        resultscsv = 'metrics.csv'
    if '-d' not in sys.argv:
        days_data = None

    print("Cluster type = ", cluster_type)

    # Form the kruize url
    form_kruize_url(cluster_type)

    # Create the performance profile
    create_performance_profile(perf_profile_json_file)
    # Create and updateResults
    createExpAndupdateResults(resultscsv,days_data,bulk_results)

if __name__ == '__main__':
    main(sys.argv[1:])
