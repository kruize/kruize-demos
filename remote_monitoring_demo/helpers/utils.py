import csv
import json
import os
import datetime
import sys
import getopt

# Convert any date format to kruize specific format
def convert_date_format(input_date_str):
    DATE_FORMATS = ["%a %b %d %H:%M:%S %Z %Y", "%Y-%m-%dT%H:%M:%S.%f", "%a %b %d %H:%M:%S UTC %Y", "%Y-%m-%d %H:%M:%S %Z", "%Y-%m-%d %H:%M:%S %z %Z"]

    for date_format in DATE_FORMATS:
        try:
            dt = datetime.datetime.strptime(input_date_str, date_format)
            dt_utc = dt.astimezone(datetime.timezone.utc)
            output_date_str = dt_utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")
            return output_date_str
        except ValueError:
            continue
    raise ValueError(f"Unrecognized date format: {input_date_str} ")

# Convert the csv to json
def create_json_from_csv(csv_file_path, outputjsonfile):
    json_data = []
    deployments = []
    mebibyte = 1048576

    with open(csv_file_path, 'r') as csvfile:
        csvreader = csv.DictReader(csvfile)

        for row in csvreader:
            container_metrics_all = {}
            container_metrics = []

            if row["cpu_request_container_avg"]:
                container_metrics.append({
			"name": "cpuRequest",
                        "results": {
                            "aggregation_info": {
                                "sum": float(row["cpu_request_container_sum"]),
                                "avg": float(row["cpu_request_container_avg"]),
                                "format": "cores"
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
                                "format": "cores"
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
                                "format": "cores"
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
                            "format": "cores"
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
                                "format": "MiB"
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
                                "format": "MiB"
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
                            "format": "MiB"
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
                            "format": "MiB"
                        }
                    }
                })

            container = {
                "container_image_name": row["image_name"],
                "container_name": row["container_name"],
                "metrics": container_metrics
            }

            containers = [container]
            kubernetes_object = {
                "type": row["k8_object_type"],
                "name": row["k8_object_name"],
                "namespace": row["namespace"],
                "containers": containers
            }
            kubernetes_objects = [kubernetes_object]
            experiment = {
                "version": "v2.0",
                "experiment_name": row["k8_object_name"] + '|' + row["k8_object_type"] + '|' + row["namespace"],
                "interval_start_time": convert_date_format(row["interval_start"]),
                "interval_end_time": convert_date_format(row["interval_end"]),
                "kubernetes_objects": kubernetes_objects
            }
            json_data.append(experiment)

    with open(outputjsonfile, "w") as json_file:
        json.dump(json_data, json_file)


#create_json_from_csv('../csv_data/rhsso-operator_deployment_sso.csv', 'finaldata.csv')
