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

            if "accelerator_core_usage_percentage_max" in row and row["accelerator_core_usage_percentage_max"]:
                if "node" in row and row["node"]:
                    container_metrics.append({
                        "name" : "acceleratorCoreUsage",
                        "results": {
                            "metadata": {
                                "accelerator_model_name": row["accelerator_model_name"],
                                "node": row["node"]
                            },
                            "aggregation_info": {
                                "min": float(row["accelerator_core_usage_percentage_min"]),
                                "max": float(row["accelerator_core_usage_percentage_max"]),
                                "avg": float(row["accelerator_core_usage_percentage_avg"]),
                                "format": "percentage"
                            }
                        }
                    })
                else:
                    container_metrics.append({
                        "name" : "acceleratorCoreUsage",
                        "results": {
                            "metadata": {
                                "accelerator_model_name": row["accelerator_model_name"]
                            },
                            "aggregation_info": {
                                "min": float(row["accelerator_core_usage_percentage_min"]),
                                "max": float(row["accelerator_core_usage_percentage_max"]),
                                "avg": float(row["accelerator_core_usage_percentage_avg"]),
                                "format": "percentage"
                            }
                        }
                    })

            if "accelerator_memory_copy_percentage_max" in row and row["accelerator_memory_copy_percentage_max"]:
                if "node" in row and row["node"]:
                    container_metrics.append({
                        "name" : "acceleratorMemoryUsage",
                        "results": {
                            "metadata": {
                                "accelerator_model_name": row["accelerator_model_name"],
                                "node": row["node"]
                            },
                            "aggregation_info": {
                                "min": float(row["accelerator_memory_copy_percentage_min"]),
                                "max": float(row["accelerator_memory_copy_percentage_max"]),
                                "avg": float(row["accelerator_memory_copy_percentage_avg"]),
                                "format": "percentage"
                            }
                        }
                    })
                else:
                    container_metrics.append({
                        "name" : "acceleratorMemoryUsage",
                        "results": {
                            "metadata": {
                                "accelerator_model_name": row["accelerator_model_name"]
                            },
                            "aggregation_info": {
                                "min": float(row["accelerator_memory_copy_percentage_min"]),
                                "max": float(row["accelerator_memory_copy_percentage_max"]),
                                "avg": float(row["accelerator_memory_copy_percentage_avg"]),
                                "format": "percentage"
                            }
                        }
                    })
            if "accelerator_frame_buffer_usage_max" in row and row["accelerator_frame_buffer_usage_max"]:
                if "node" in row and row["node"]:
                    container_metrics.append({
                        "name" : "acceleratorFrameBufferUsage",
                        "results": {
                            "metadata": {
                                "accelerator_model_name": row["accelerator_model_name"],
                                "node": row["node"]
                            },
                            "aggregation_info": {
                                "min": float(row["accelerator_frame_buffer_usage_min"]),
                                "max": float(row["accelerator_frame_buffer_usage_max"]),
                                "avg": float(row["accelerator_frame_buffer_usage_avg"]),
                                "format": "percentage"
                            }
                        }
                    })
                else:
                    container_metrics.append({
                        "name" : "acceleratorFrameBufferUsage",
                        "results": {
                            "metadata": {
                                "accelerator_model_name": row["accelerator_model_name"]
                            },
                            "aggregation_info": {
                                "min": float(row["accelerator_frame_buffer_usage_min"]),
                                "max": float(row["accelerator_frame_buffer_usage_max"]),
                                "avg": float(row["accelerator_frame_buffer_usage_avg"]),
                                "format": "percentage"
                            }
                        }
                    })

            container = {
                "container_image_name": row["image_name"],
                "container_name": row["container_name"],
                "metrics": container_metrics
            }

            # Choose type and name based on available keys
            workload_type = row.get("k8_object_type") or row.get("workload_type")
            workload_name = row.get("k8_object_name") or row.get("workload")

            containers = [container]
            kubernetes_object = {
                "type": workload_type,
                "name": workload_name,
                "namespace": row["namespace"],
                "containers": containers
            }
            kubernetes_objects = [kubernetes_object]
            experiment = {
                "version": "v2.0",
                "experiment_name": f"{workload_name}|{workload_type}|{row['namespace']}",
                "interval_start_time": convert_date_format(row["interval_start"]),
                "interval_end_time": convert_date_format(row["interval_end"]),
                "kubernetes_objects": kubernetes_objects
            }
            json_data.append(experiment)

    with open(outputjsonfile, "w") as json_file:
        json.dump(json_data, json_file)


#create_json_from_csv('../csv_data/rhsso-operator_deployment_sso.csv', 'finaldata.csv')

# Create results json for namespace experiment from csv
def create_namespace_json_from_csv(csv_file_path, outputjsonfile):

    # Check if output file already exists. If yes, delete that.
    if os.path.exists(outputjsonfile):
        os.remove(outputjsonfile)

    # Define the list that will hold the final JSON data
    json_data = []

    mebibyte = 1048576

    with open(csv_file_path, 'r') as csvfile:
        csvreader = csv.DictReader(csvfile)

        for row in csvreader:
            namespace_metrics_all = {}
            namespace_metrics = []

            columns_tocheck = ["namespace", "cluster_name"]
            namespace = "clowder-system"
            cluster_name = "e23-alias"

            for col in columns_tocheck:
                if col not in row:
                    if col == "namespace":
                        row[col] = namespace
                    elif col == "cluster_name":
                        row[col] = cluster_name

            if row["cpu_request_namespace_sum"]:
                namespace_metrics.append({
                    "name": "namespaceCpuRequest",
                    "results": {
                        "aggregation_info": {
                            "sum": float(row["cpu_request_namespace_sum"]),
                            "format": "cores"
                        }
                    }
                })
            if row["cpu_limit_namespace_sum"]:
                namespace_metrics.append({
                    "name" : "namespaceCpuLimit",
                    "results": {
                        "aggregation_info": {
                            "sum": float(row["cpu_limit_namespace_sum"]),
                            "format": "cores"
                        }
                    }
                })
            if row["cpu_throttle_namespace_min"] and row["cpu_throttle_namespace_max"]:
                namespace_metrics.append({
                    "name" : "namespaceCpuThrottle",
                    "results": {
                        "aggregation_info": {
                            "min": float(row["cpu_throttle_namespace_min"]),
                            "max": float(row["cpu_throttle_namespace_max"]),
                            "avg": float(row["cpu_throttle_namespace_avg"]),
                            "format": "cores"
                        }
                    }
                })
            elif row["cpu_throttle_namespace_max"]:
                namespace_metrics.append({
                    "name" : "namespaceCpuThrottle",
                    "results": {
                        "aggregation_info": {
                            "max": float(row["cpu_throttle_namespace_max"]),
                            "avg": float(row["cpu_throttle_namespace_avg"]),
                            "format": "cores"
                        }
                    }
                })

            if row["cpu_usage_namespace_avg"]:
                namespace_metrics.append({
                    "name" : "namespaceCpuUsage",
                    "results": {
                        "aggregation_info": {
                            "min": float(row["cpu_usage_namespace_min"]),
                            "max": float(row["cpu_usage_namespace_max"]),
                            "avg": float(row["cpu_usage_namespace_avg"]),
                            "format": "cores"
                        }
                    }
                })
            if row["memory_request_namespace_sum"]:
                namespace_metrics.append({
                    "name" : "namespaceMemoryRequest",
                    "results": {
                        "aggregation_info": {
                            "sum": float(row["memory_request_namespace_sum"])/mebibyte,
                            "format": "MiB"
                        }
                    }
                })
            if row["memory_limit_namespace_sum"]:
                namespace_metrics.append({
                    "name" : "namespaceMemoryLimit",
                    "results": {
                        "aggregation_info": {
                            "sum": float(row["memory_limit_namespace_sum"])/mebibyte,
                            "format": "MiB"
                        }
                    }
                })
            if row["memory_usage_namespace_avg"]:
                namespace_metrics.append({
                    "name" : "namespaceMemoryUsage",
                    "results": {
                        "aggregation_info": {
                            "min": float(row["memory_usage_namespace_min"])/mebibyte,
                            "max": float(row["memory_usage_namespace_max"])/mebibyte,
                            "avg": float(row["memory_usage_namespace_avg"])/mebibyte,
                            "format": "MiB"
                        }
                    }
                })
            if row["memory_rss_usage_namespace_avg"]:
                namespace_metrics.append({
                    "name" : "namespaceMemoryRSS",
                    "results": {
                        "aggregation_info": {
                            "min": float(row["memory_rss_usage_namespace_min"])/mebibyte,
                            "max": float(row["memory_rss_usage_namespace_max"])/mebibyte,
                            "avg": float(row["memory_rss_usage_namespace_avg"])/mebibyte,
                            "format": "MiB"
                        }
                    }
                })

            # Create a dictionary to hold the container information
            namespace = {
                "namespace": row["namespace"],
                "metrics": namespace_metrics
            }

            # Create a list to hold the containers
            namespaces = [namespace]

            # Create a dictionary to hold the deployment information
            kubernetes_object = {
                "namespaces": namespace
            }
            kubernetes_objects = [kubernetes_object]

            # Create a dictionary to hold the experiment data
            experiment = {
                "version": "v2.0",
                "experiment_name": row["cluster_name"] + '|' + row["namespace"],
                "interval_start_time": convert_date_format(row["start_timestamp"]),
                "interval_end_time": convert_date_format(row["end_timestamp"]),
                "kubernetes_objects": kubernetes_objects
            }

            json_data.append(experiment)
    with open(outputjsonfile, "w") as json_file:
        json.dump(json_data, json_file)
