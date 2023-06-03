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


def form_kruize_url(cluster_type):
    global URL
    if (cluster_type == "minikube"):
        port = subprocess.run(['kubectl -n monitoring get svc kruize --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort'], shell=True, stdout=subprocess.PIPE)

        AUTOTUNE_PORT=port.stdout.decode('utf-8').strip('\n')

        ip = subprocess.run(['minikube ip'], shell=True, stdout=subprocess.PIPE)
        SERVER_IP=ip.stdout.decode('utf-8').strip('\n')

    elif (cluster_type == "openshift"):
        port = subprocess.run(['kubectl -n openshift-tuning get svc kruize --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort'], shell=True, stdout=subprocess.PIPE)

        AUTOTUNE_PORT=port.stdout.decode('utf-8').strip('\n')
        print("PORT = ", AUTOTUNE_PORT)

        ip = subprocess.run(['kubectl get pods -l=app=kruize -o wide -n openshift-tuning -o=custom-columns=NODE:.spec.nodeName --no-headers'], shell=True, stdout=subprocess.PIPE)
        SERVER_IP=ip.stdout.decode('utf-8').strip('\n')
        print("IP = ", SERVER_IP)

    URL = "http://" + str(SERVER_IP) + ":" + str(AUTOTUNE_PORT)
    print (f"\nKRUIZE AUTOTUNE URL = {URL}")


def create_experiment(input_json_file):
    """
    Description: This function validates the input json and posts 
    the experiment using createExperiment API to Kruize
    Input Parameters: experiment input json
    """

    json_file = open(input_json_file)
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
        print(f"URL = {url}")

        response = requests.post(url, json=input_json)
        print(f"Response status code = {response.status_code}")
        print(response.text)

def update_results(result_json_file):
    """
    Description: This function validates the result json and 
    posts the experiment results using updateResults API to Kruize
    Input Parameters: resource usage metrics json
    """

    # read the json
    json_file = open(result_json_file, "r")
    result_json = json.loads(json_file.read())
    
    # TO DO: Validate the result json

    print("\nUpdating the results...")
    url = URL + "/updateResults"
    print(f"URL = {url}")

    response = requests.post(url, json=result_json)
    print(f"Response status code = {response.status_code}")
    print(response.text)
    return response

def list_recommendations(experiment_name):
    """
    Description: This function obtains the recommendations 
    from Kruize using listRecommendations API
    Input Parameters: experiment name, deployment name and namespace
    """

    print("\nListing the recommendations...")
    url = URL + "/listRecommendations"
    print(f"URL = {url}")

    PARAMS = {'experiment_name': experiment_name}
    response = requests.get(url = url, params = PARAMS)
    print(f"Response status code = {response.status_code}")

    return response.json()

def create_performance_profile(perf_profile_json_file):
    """
    Description: This function creates a performance profile
    using the Kruize createPerformanceProfile API
    Input Parameters: performance profile json
    """

    json_file = open(perf_profile_json_file)
    perf_profile_json = json.loads(json_file.read())

    print("\nCreating performance profile...")
    url = URL + "/createPerformanceProfile"
    print(f"URL = {url}")

    response = requests.post(url, json=perf_profile_json)
    print(f"Response status code = {response.status_code}")
    print(response.text)
    return response

def list_experiments():
    """
    Description: This function obtains the experiments and
    result metrics from Kruize using listExperiments API
    """

    print("\nListing the experiments...")
    url = URL + "/listExperiments"
    print(f"URL = {url}")

    response = requests.get(url = url)
    print(f"Response status code = {response.status_code}")

    return response.json()

def combine_jsons(result_json, reco_json):
    """
    Description: This function combines the metric
    results and recommendations into a single json
    Input parameters: result json file, recommendations json
    """

    input_json = open(result_json)
    data = json.loads(input_json.read())

    exp = "quarkus-resteasy-autotune-min-http-response-time-db"

    combined_data = {"recommendations": reco_json[exp]}
    data[0].update(combined_data)

    return data[0]
