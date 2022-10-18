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

from kruize.autotune import *
import sys, getopt

def main(argv):
    cluster_type="minikube"
    result_json_file="result.json"
    input_json_file="input.json"

    try:
        opts, args = getopt.getopt(argv,"hi:r:c:")
    except getopt.GetoptError:
        print("demo.py -c <cluster type> -i <input json> -r <result json>")
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print("demo.py -c <cluster type> -i <input json> -r <result json>")
            sys.exit()
        elif opt == '-c':
            cluster_type = arg
        elif opt == '-i':
            input_json_file = arg
        elif opt == '-r':
            result_json_file = arg

    print("Cluster type = ", cluster_type)
    print("Input json = ", input_json_file)
    print("Result json =", result_json_file)

    form_autotune_url(cluster_type)

    # Create experiment using the specified json
    create_experiment(input_json_file)

    # Post the experiment results
    update_results(result_json_file)
    
    # Get the recommendations
    list_recommendations()


if __name__ == '__main__':
	main(sys.argv[1:])
