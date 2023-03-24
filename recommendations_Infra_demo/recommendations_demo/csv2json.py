import csv
import json
import sys
import os
import datetime
import getopt


def convert_date_format(input_date_str):
    try:
        input_date = datetime.datetime.strptime(input_date_str, "%a %b %d %H:%M:%S UTC %Y")
    except ValueError:
        time_obj = datetime.datetime.strptime(input_date_str, '%Y-%m-%dT%H:%M:%S.%f')
        input_date = time_obj.astimezone(datetime.timezone.utc)
    
    output_date_str = input_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')
    return output_date_str


def create_json_from_csv(csv_file_path):
    # Define the list that will hold the final JSON data
    json_data = []

    # Create an empty list to hold the deployments
    deployments = []
    mebibyte = 1048576

    # Open the CSV file
    with open(csv_file_path, 'r') as csvfile:
        # Create a CSV reader object
        csvreader = csv.DictReader(csvfile)

        for row in csvreader:
            container_metrics_all = {}
            container_metrics = []

	## Hardcoding for tfb-results. Will automate
            row["image_name"] = "kruize/tfb-qrh:2.9.1.F"
            row["container_name"] = "tfb-server"
            row["k8_object_type"] = "deployment"
            row["k8_object_name"] = "tfb-qrh"
            row["namespace"] = "autotune-tfb"
		
            if row["cpu_request_container_avg"]:
                container_metrics.append({
			"name": "cpuRequest",
                        "results": {
                            "aggregation_info": {
                                "sum": float(row["cpu_request_container_sum"]),
                                "avg": float(row["cpu_request_container_avg"]),
                                "units": "cores"
                                }
                            }
			})
            if row["cpu_limit_container_avg"]:
                container_metrics.append({
			"name" : "cpuLimit",
                        "results": {
                            "aggregation_info": {
                                "sum": float(row["cpu_limit_container_sum"]),
                                "avg": float(row["cpu_limit_container_avg"]),
                                "units": "cores"
                                }
                            }
                        })
            if row["cpu_throttle_container_max"]:
                container_metrics.append({
			"name" : "cpuThrottle",
                        "results": {
                            "aggregation_info": {
                                "sum": float(row["cpu_throttle_container_sum"]),
                                "max": float(row["cpu_throttle_container_max"]),
                                "avg": float(row["cpu_throttle_container_avg"]),
                                "units": "cores"
                                }
                            }
                        })
            container_metrics.append({
		    "name" : "cpuUsage",
                    "results": {
                        "aggregation_info": {
                            "sum": float(row["cpu_usage_container_sum"]),
                            "min": float(row["cpu_usage_container_min"]),
                            "max": float(row["cpu_usage_container_max"]),
                            "avg": float(row["cpu_usage_container_avg"]),
                            "units": "cores"
                            }
                        }
                    })            
            if row["memory_request_container_avg"]:
                container_metrics.append({
			"name" : "memoryRequest",
                        "results": {
                            "aggregation_info": {
                                "sum": float(row["memory_request_container_sum"])/mebibyte,
                                "avg": float(row["memory_request_container_avg"])/mebibyte,
                                "units": "MiB"
                                }
                            }
                        })
            if row["memory_limit_container_avg"]:
                container_metrics.append({
			"name" : "memoryLimit",
                        "results": {
                            "aggregation_info": {
                                "sum": float(row["memory_limit_container_sum"])/mebibyte,
                                "avg": float(row["memory_limit_container_avg"])/mebibyte,
                                "units": "MiB"
                                }
                            }
                        })
            container_metrics.append({
		    "name" : "memoryUsage",
                    "results": {
                        "aggregation_info": {
                            "min": float(row["memory_usage_container_min"])/mebibyte,
                            "max": float(row["memory_usage_container_max"])/mebibyte,
                            "sum": float(row["memory_usage_container_sum"])/mebibyte,
                            "avg": float(row["memory_usage_container_avg"])/mebibyte,
                            "units": "MiB"
                        }
                    }
                })
            container_metrics.append({
		    "name" : "memoryRSS",
                    "results": {
                        "aggregation_info": {
                            "min": float(row["memory_rss_usage_container_min"])/mebibyte,
                            "max": float(row["memory_rss_usage_container_max"])/mebibyte,
                            "sum": float(row["memory_rss_usage_container_sum"])/mebibyte,
                            "avg": float(row["memory_rss_usage_container_avg"])/mebibyte,
                            "units": "MiB"
                        }
                    }
                })
            
            #if container_metrics:
            #    container_metrics_all["metrics"].update(container_metrics)
           
            # Create a dictionary to hold the container information
            container = {
                "container_image_name": row["image_name"],
                "container_name": row["container_name"],
                "metrics": container_metrics
            }
            
            # Create a list to hold the containers
            containers = [container]
            
            # Create a dictionary to hold the deployment information
            kubernetes_object = {
                "type": row["k8_object_type"],
                "name": row["k8_object_name"],
                "namespace": row["namespace"],
                "containers": containers
            }
            kubernetes_objects = [kubernetes_object]

            # Create a dictionary to hold the experiment data
            experiment = {
                "version": "1.0",
                "experiment_name": "tfb-qrh",
                "start_timestamp": convert_date_format(row["start_timestamp"]),
                "end_timestamp": convert_date_format(row["end_timestamp"]),
                "kubernetes_objects": kubernetes_objects
            }
            
            json_data.append(experiment)

    # Write the final JSON data to the output file
    with open(outputjsonfile, "w") as json_file:
        json.dump(json_data, json_file)


filename = sys.argv[1]
outputjsonfile = sys.argv[2]

# Check if output file already exists. If yes, delete that.
if os.path.exists(outputjsonfile):
    os.remove(outputjsonfile)

create_json_from_csv(filename)


