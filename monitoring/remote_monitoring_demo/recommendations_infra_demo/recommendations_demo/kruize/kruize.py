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

from . json_validate import validate_exp_input_json
import subprocess
import requests
import json
import os
import time
import shutil


def form_kruize_url(cluster_type):
    global URL
    if (cluster_type == "minikube"):
        port = subprocess.run(['kubectl -n monitoring get svc kruize --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort'], shell=True, stdout=subprocess.PIPE)

        AUTOTUNE_PORT=port.stdout.decode('utf-8').strip('\n')

        ip = subprocess.run(['minikube ip'], shell=True, stdout=subprocess.PIPE)
        SERVER_IP=ip.stdout.decode('utf-8').strip('\n')

        URL = "http://" + str(SERVER_IP) + ":" + str(AUTOTUNE_PORT)

    elif (cluster_type == "openshift"):
        #port = subprocess.run(['kubectl -n openshift-tuning get svc kruize --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort'], shell=True, stdout=subprocess.PIPE)

        #AUTOTUNE_PORT=port.stdout.decode('utf-8').strip('\n')
        #print("PORT = ", AUTOTUNE_PORT)

        #ip = subprocess.run(['kubectl get pods -l=app=kruize -o wide -n openshift-tuning -o=custom-columns=NODE:.spec.nodeName --no-headers'], shell=True, stdout=subprocess.PIPE)
        #SERVER_IP=ip.stdout.decode('utf-8').strip('\n')
        #print("IP = ", SERVER_IP)
        port = subprocess.run(['oc expose svc/kruize -n openshift-tuning'], shell=True, stdout=subprocess.PIPE)
        kruize_URL = subprocess.run(['oc status -n openshift-tuning | grep "svc/kruize[^-]" | cut -d " " -f1'], shell=True, stdout=subprocess.PIPE)
        URL = kruize_URL.stdout.decode('utf-8').strip('\n')

#    URL = "http://" + str(SERVER_IP) + ":" + str(AUTOTUNE_PORT)
    print ("\nKRUIZE AUTOTUNE URL = ", URL)
    return URL


# Description: This function validates the input json and posts the experiment using createExperiment API to Kruize
# Input Parameters: experiment input json
def create_experiment(input_json_file):

    json_file = open(input_json_file, "r")
    input_json = json.loads(json_file.read())
    print("\n************************************************************")
    print(input_json)
    print("\n************************************************************")

    # Validate the json
    print("\nValidating the input json...")
    isInvalid = validate_exp_input_json(input_json)
    if isInvalid:
        print(isInvalid)
        print("Input Json is invalid")
        exit(1)
    else:
        # read the json
        print("\nCreating the experiment...")

        url = URL + "/createExperiment"
        response = requests.post(url, json=input_json)
        print("URL = ", url, "   Response status code = ", response.status_code)
        print(response.text)

# Description: This function validates the result json and posts the experiment results using updateResults API to Kruize
# Input Parameters: resource usage metrics json
def update_results(result_json_file):
    # read the json
    json_file = open(result_json_file, "r")
    result_json = json.loads(json_file.read())
    
    # TO DO: Validate the result json

    print("\nUpdating the results...")
    url = URL + "/updateResults"
    response = requests.post(url, json=result_json)
    print("URL = ", url, "  Response status code = ", response.status_code)
    print(response.text)
    return response

# Description: This function generates the recommendations for an experiment
# Input Parameters: experiment_name , interval_end time
def update_recommendations(experiment_name, end_time=None):
    print("\nUpdating the Recommendations...")
    url = URL + "/updateRecommendations"
    if end_time is not None:
        PARAMS = {'experiment_name':experiment_name,'interval_end_time':end_time}
    else:
        PARAMS = {'experiment_name':experiment_name}

    response = requests.post(url, params = PARAMS )
    print("URL = ", url, "  Response status code = ", response.status_code)
    print(response.text)
    return response

# Description: This function obtains the recommendations from Kruize using listRecommendations API
# Input Parameters: experiment name
def list_recommendations(experiment_name):
    print("\nListing the recommendations...")
    url = URL + "/listRecommendations"
    PARAMS = {'experiment_name': experiment_name}
    response = requests.get(url = url, params = PARAMS)
    print("URL = ", url, "  Response status code = ", response.status_code)
    return response.json()

# Description: This function creates a performance profile using the Kruize createPerformanceProfile API
# Input Parameters: performance profile json
def create_performance_profile(perf_profile_json_file):
    json_file = open(perf_profile_json_file, "r")
    perf_profile_json = json.loads(json_file.read())

    print("\nCreating performance profile...")
    url = URL + "/createPerformanceProfile"
    response = requests.post(url, json=perf_profile_json)
    print("URL = ", url , "   Response status code = ", response.status_code)
    print(response.text)
    return response

# Description: This function obtains the experiments from Kruize using listExperiments API
def list_experiments():
    print("\nListing the experiments...")
    url = URL + "/listExperiments"
    response = requests.get(url = url)
    print("URL = ", url, "   Response status code = ", response.status_code)

    return response.json()

# Description: This function obtains the result metrics and recommendations from Kruize using listExperiments API for an experiment.
def list_metrics_with_recommendations(experiment_name):
    print("\nListing the experiments with metrics and recommendations...")
    url = URL + "/listExperiments"
    PARAMS = {'results':'true','recommendations':'true','latest':'false','experiment_name':experiment_name}
    response = requests.get(url = url, params = PARAMS)
    print("URL = ", url, "   Response status code = ", response.status_code)
    return response.json()

def list_clusters():
    print("\nListing the clusters...")
    url = URL + "/listClusters"
    response = requests.get(url = url)
    print("URL = ", url,"   Response status code = ", response.status_code)
    return response.json()

def summarize_cluster_data(cluster_name=None,namespace_name=None):
    print("\nSummarizing the cluster data...")
    PARAMS = {'summarize_type':'cluster'}
    url = URL + "/summarize"
    if cluster_name is not None and namespace_name is None:
        PARAMS = {'summarize_type':'cluster', 'cluster_name':cluster_name}
    elif cluster_name is not None and namespace_name is not None:
        PARAMS = {'summarize_type':'namespace','cluster_name':cluster_name, 'namespace_name':namespace_name}
    response = requests.get(url = url, params = PARAMS)
    print("URL = ", url,  "PARAMS = ",PARAMS ,"   Response status code = ", response.status_code)
    return response.json()

def summarize_namespace_data(namespace_name=None):
    print("\nSummarizing the namespace data...")
    url = URL + "/summarize"
    PARAMS = {'summarize_type':'namespace'}
    if namespace_name is not None:
        PARAMS = {'summarize_type':'namespace','namespace_name':namespace_name}
    response = requests.get(url = url, params = PARAMS)
    print("URL = ", url,  "PARAMS = ",PARAMS ,"   Response status code = ", response.status_code)
    return response.json()

# Description: This function combines the metric results and recommendations into a single json
# Input parameters: result json file, recommendations json
def combine_jsons(result_json, reco_json):

    input_json = open(result_json, "r")
    data = json.loads(input_json.read())

    exp = "quarkus-resteasy-autotune-min-http-response-time-db"

    combined_data = {"recommendations": reco_json[exp]}
    data[0].update(combined_data)

    return data[0]
