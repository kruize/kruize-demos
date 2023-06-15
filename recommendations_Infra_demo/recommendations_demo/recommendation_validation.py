import pandas as pd
import json
import csv
import sys
import os
import datetime
import getopt


# Validate the recommendations generated to the csv created by scripts(which contains the recommendation logic)
def validate_recomm(filename):
    # Load the JSON data
    with open(filename, 'r') as f:
       data = json.load(f)
    df = pd.read_csv('recommendation_check.csv')
    # Compare the data for each time zone
    for json_data in data:
        for kubernetes_object in json_data[0]["kubernetes_objects"]:
            for container in kubernetes_object["containers"]:
                for time_zone in container["recommendations"]["data"]:
                    for duration_type in container["recommendations"]["data"][time_zone]["duration_based"]:
                        recommendations = container["recommendations"]["data"][time_zone]
                        if "config" in recommendations["duration_based"][duration_type]:
                            cpu_limits_json = round(recommendations["duration_based"][duration_type]["config"]["limits"]["cpu"]["amount"], 4)
                            memory_limits_json = round(recommendations["duration_based"][duration_type]["config"]["limits"]["memory"]["amount"], 4)
                            cpu_requests_json = round(recommendations["duration_based"][duration_type]["config"]["requests"]["cpu"]["amount"], 4)
                            memory_requests_json = round(recommendations["duration_based"][duration_type]["config"]["requests"]["memory"]["amount"], 4)
                            
                            
                            # Compare the CPU and memory values with the corresponding values in the CSV file
                            csv_row = df.loc[(df["time_zone"] == time_zone) & (df["term"] == duration_type)]
                            if len(csv_row) > 0:
                                cpu_limits_csv = round(csv_row["cpu_limits"].values[0], 4)
                                memory_limits_csv = round(csv_row["memory_limits"].values[0], 4)
                                cpu_requests_csv = round(csv_row["cpu_requests"].values[0], 4)
                                memory_requests_csv = round(csv_row["memory_requests"].values[0], 4)
                                
                                if cpu_limits_json == cpu_limits_csv and memory_limits_json == memory_limits_csv and cpu_requests_json == cpu_requests_csv and memory_requests_json == memory_requests_csv :
                                    print(f"Match found for timezone {time_zone} and duration type {duration_type}")
                            else:
                                print(f"No match found for timezone {time_zone} and duration type {duration_type}")


# Convert the recommendations json to csv to visualize the data manually.
def update_recomm_csv(filename):
    # Load the JSON data
    with open(filename, 'r') as f:
      data = json.load(f)

#    experiment_name_exists = False
#    for reco in data:
#        if 'experiment_name' in reco:
#            experiment_name_exists = True
#            break
    
    # Exit the function if experiment_key doesn't exist
#    if not experiment_name_exists:
#        print("The experiment key doesn't exist in the JSON data.")
#        return

    # Open a CSV file for writing
    with open('recommendationsOutput.csv', 'a', newline='') as f:
        writer = csv.writer(f)
        # Write the headers to the CSV file
        #writer.writerow(['cluster_name', 'experiment_name', 'container_name', 'time_zone', 'duration_type','cpu_requests' , 'memory_requests' , 'cpu_limits', 'memory_limits'])

        # Compare the data for each time zone
        for json_data in data:
            cluster_json = json_data[0]["cluster_name"]
            exp_name_json = json_data[0]["experiment_name"]

            for kubernetes_object in json_data[0]["kubernetes_objects"]:
                for container in kubernetes_object["containers"]:
                    container_json = container["container_name"]
                    for time_zone in container["recommendations"]["data"]:
                        for recommendation_engine in container["recommendations"]["data"][time_zone]:
                            for duration_type in container["recommendations"]["data"][time_zone][recommendation_engine]:
                                recommendations = container["recommendations"]["data"][time_zone]
                                if "config" in recommendations["duration_based"][duration_type]:
                                    cpu_limits_json = ''
                                    memory_limits_json = ''
                                    cpu_requests_json = ''
                                    memory_requests_json = ''
                                    if "cpu" in recommendations["duration_based"][duration_type]["config"]["limits"]:
                                        cpu_limits_json = round(recommendations["duration_based"][duration_type]["config"]["limits"]["cpu"]["amount"], 4)
                                    if "memory" in recommendations["duration_based"][duration_type]["config"]["limits"]:
                                        memory_limits_json = round(recommendations["duration_based"][duration_type]["config"]["limits"]["memory"]["amount"], 4)
                                    if "cpu" in recommendations["duration_based"][duration_type]["config"]["requests"]:
                                        cpu_requests_json = round(recommendations["duration_based"][duration_type]["config"]["requests"]["cpu"]["amount"], 4)
                                    if "memory" in recommendations["duration_based"][duration_type]["config"]["requests"]:
                                        memory_requests_json = round(recommendations["duration_based"][duration_type]["config"]["requests"]["memory"]["amount"], 4)
                                    
                                    writer.writerow([cluster_json, exp_name_json, container_json, time_zone, recommendation_engine, duration_type, cpu_requests_json, memory_requests_json, cpu_limits_json, memory_limits_json])


def create_recomm_csv():
    # Open a CSV file for writing
    with open('recommendationsOutput.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        # Write the headers to the CSV file
        writer.writerow(['cluster_name', 'experiment_name', 'container_name', 'time_zone', 'recommendation_engine', 'duration_type','cpu_requests' , 'memory_requests' , 'cpu_limits', 'memory_limits'])

def getUniquek8Objects(inputcsvfile):
    column_name = 'k8ObjectName'
    # Read the CSV file and get the unique values of the specified column
    unique_values = set()
    
    with open(inputcsvfile, 'r') as csv_file:
        csv_reader = csv.DictReader(csv_file)
        for row in csv_reader:
            unique_values.add(row[column_name])
    return unique_values


def aggregateWorkloads(filename, outputResults):

    print("filename is..")
    print(filename)
    print(outputResults)

    # Load the CSV file into a pandas DataFrame
    df = pd.read_csv(filename)

    #Remove the rows if there is no owner_kind, owner_name and workload
    # Expected to ignore rows which can be pods / invalid
    columns_to_check = ['owner_kind', 'owner_name', 'workload', 'workload_type']
    df = df.dropna(subset=columns_to_check, how='any')

    # Create a column with k8_object_type
    # Based on the data observed, these are the assumptions:
    # If owner_kind is 'ReplicaSet' and workload is '<none>', actual workload_type is ReplicaSet
    # If owner_kind is 'ReplicationCOntroller' and workload is '<none>', actual workload_type is ReplicationController
    # If owner_kind and workload has some names, workload_type is same as derived through queries.

    df['k8_object_type'] = ''
    for i, row in df.iterrows():
        if row['owner_kind'] == 'ReplicaSet' and row['workload'] == '<none>':
            df.at[i, 'k8_object_type'] = 'replicaset'
        elif row['owner_kind'] == 'ReplicationController' and row['workload'] == '<none>':
            df.at[i, 'k8_object_type'] = 'replicationcontroller'
        else:
            df.at[i, 'k8_object_type'] = row['workload_type']

    # Update k8_object_name based on the type and workload.
    # If the workload is <none> (which indicates ReplicaSet and ReplicationCOntroller - ignoring pods/invalid cases), the name of the k8_object can be owner_name.
    # If the workload has some other name, the k8_object_name is same as workload. In this case, owner_name cannot be used as there can be multiple owner_names for the same deployment(considering there are multiple replicasets)

    df['k8_object_name'] = ''
    for i, row in df.iterrows():
        if row['workload'] != '<none>':
            df.at[i, 'k8_object_name'] = row['workload']
        else:
            df.at[i, 'k8_object_name'] = row['owner_name']

    df.to_csv('cop-withobjType.csv', index=False)

    # Specify the columns to sort by
    # Sort and grpup the data based on below columns to get a container for a workload and for an interval.
    # Each file generated is for a single timestamp and a container for a workload and will be aggregated to a single metrics value.
    #sort_columns = ['namespace', 'k8_object_type', 'owner_name', 'image_name', 'container_name', 'interval_start']
    sort_columns = ['namespace', 'k8_object_type', 'workload', 'container_name', 'interval_start']
    sorted_df = df.sort_values(sort_columns)

    # Group the rows by the unique values
    grouped = sorted_df.groupby(sort_columns)

    # Create a directory to store the output CSV files
    output_dir = 'output'
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Write each group to a separate CSV file
    counter = 0
    for key, group in grouped:
        counter += 1
        filename = f"file_{counter}.csv"
        #    filename = '_'.join(str(x) for x in key) + '.csv'
        filepath = os.path.join(output_dir, filename)
        group.to_csv(filepath, index=False)

    #Create a temporary file with a header to append the aggregate data from multiple files.
    # Extract the header row
    header_row = df.columns.tolist()
    agg_df = pd.DataFrame(columns=header_row)
    columns_to_ignore = ['pod', 'owner_name', 'node']
    if 'resource_id' in df.columns:
        columns_to_ignore.append('resource_id')
        #columns_to_ignore = ['pod', 'owner_name', 'node' , 'resource_id']

    for filename in os.listdir(output_dir):
        if filename.endswith('.csv'):
            filepath = os.path.join(output_dir, filename)
            df = pd.read_csv(filepath)

            # Calculate the average and minimum values for specific columns
            for column in df.columns:
                if column.endswith('avg'):
                    avg = df[column].mean()
                    df[column] = avg
                elif column.endswith('min'):
                    minimum = df[column].min()
                    df[column] = minimum
                elif column.endswith('max'):
                    maximum = df[column].max()
                    df[column] = maximum
                elif column.endswith('sum'):
                    total = df[column].sum()
                    df[column] = total

            df = df.drop_duplicates(subset=[col for col in df.columns if col not in columns_to_ignore])
            agg_df = agg_df.append(df)

    agg_df.to_csv('./final.csv', index=False)
    #columns_to_ignore = ['pod', 'owner_name', 'node' , 'resource_id']
    # Drop the columns like mentioned as they are only one of the value for a workload type.
    # For a deployment work_type, only one pod value is picked irrespective of multiple pods as the metrics are aggregated. This is optional

    df1 = pd.read_csv('final.csv')
    df1.drop(columns_to_ignore, axis=1, inplace=True)
    df1.to_csv(outputResults, index=False)


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


def create_json_from_csv(csv_file_path, outputjsonfile):

    # Check if output file already exists. If yes, delete that.
    ## TODO: Recheck if this is necessary
    if os.path.exists(outputjsonfile):
        os.remove(outputjsonfile)

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

	## Hardcoding for tfb-results and demo benchmark. Updating them only if these columns are not available.
        ## Keep this until the metrics queries are fixed in benchmark to get the below column data
            columns_tocheck = [ "image_name" , "container_name" , "k8_object_type" , "k8_object_name" , "namespace" ]
            for col in columns_tocheck:
               if col not in row:
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
            if row["cpu_usage_container_avg"]:
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
            if row["memory_usage_container_avg"]:
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
            if row["memory_usage_container_avg"]:
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
                "experiment_name": row["k8_object_name"] + '|' + row["k8_object_type"] + '|' + row["namespace"],
                "interval_start_time": convert_date_format(row["start_timestamp"]),
                "interval_end_time": convert_date_format(row["end_timestamp"]),
                #"start_timestamp": convert_date_format(row["start_timestamp"]),
                #"end_timestamp": convert_date_format(row["end_timestamp"]),
                #"interval_start_time": row["start_timestamp"],
                #"interval_end_time": row["end_timestamp"],
                "kubernetes_objects": kubernetes_objects
            }

            json_data.append(experiment)

    # Write the final JSON data to the output file
    with open(outputjsonfile, "w") as json_file:
        json.dump(json_data, json_file)


## Get the metrics and recommendations data from listExperiments
def getExperimentMetrics(filename):
    # Load the JSON data
    with open(filename, 'r') as f:
      data = json.load(f)
    if not data:
        print("No experiments found!")
    else:
        with open('experimentMetrics.csv', 'w', newline='') as f:
            fieldnames = ['experiment_name', 'namespace', 'type', 'name', 'container_name', 'timezone', 'cpuUsage_sum', 'cpuUsage_avg', 'cpuUsage_max', 'cpuUsage_min', 'cpuThrottle_sum', 'cpuThrottle_avg', 'cpuThrottle_max', 'cpuRequest_sum', 'cpuRequest_avg', 'cpuLimit_sum', 'cpuLimit_avg', 'memoryRSS_sum', 'memoryRSS_avg', 'memoryRSS_max', 'memoryRSS_min', 'memoryUsage_sum', 'memoryUsage_avg', 'memoryUsage_max', 'memoryUsage_min', 'memoryRequest_sum', 'memoryRequest_avg',  'memoryLimit_sum', 'memoryLimit_avg', 'duration_based_short_term_cpu_requests', 'duration_based_short_term_memory_requests', 'duration_based_short_term_cpu_limits', 'duration_based_short_term_memory_limits', 'duration_based_medium_term_cpu_requests', 'duration_based_medium_term_memory_requests', 'duration_based_medium_term_cpu_limits', 'duration_based_medium_term_memory_limits', 'duration_based_long_term_cpu_requests', 'duration_based_long_term_memory_requests', 'duration_based_long_term_cpu_limits', 'duration_based_long_term_memory_limits', 'cpuUsage_format', 'memoryRequest_format', 'memoryRSS_format', 'cpuThrottle_format', 'memoryLimit_format', 'cpuLimit_format', 'memoryUsage_format', 'cpuRequest_format']
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            # Write the headers to the CSV file
            writer.writeheader()

            datadict = data[0]
            for key, value in datadict.items():
                if key == "experiment_name":
                    experiment_name = value
                if key == "kubernetes_objects":
                    for kobj in value:
                        containerNames=[]
                        k8ObjectName = ""
                        namespace = ""
                        k8ObjectType = ""
                        k8ObjectName = kobj["name"]
                        namespace = kobj["namespace"]
                        k8ObjectType = kobj["type"]
                        for container_name,container_data in kobj["containers"].items():
                            containerName = container_data["container_name"]
                            containerNames.append(containerName)
                            for timezone, timezone_data in container_data["results"].items():
                                kobj_dict = {
                                'experiment_name': experiment_name,
                                'type': kobj["type"],
                                'name': kobj["name"],
                                'namespace': kobj["namespace"],
                                'container_name': container_data["container_name"],
                                'timezone': timezone,
                                }
                                metric_dict = {}
                                recomm_dict = {}
                                for metric_name, metric_data in timezone_data["metrics"].items():
                                    for agg_name, agg_value in metric_data["aggregation_info"].items():
                                        metric_agg_var_name = metric_name + '_' + agg_name
                                        metric_dict[metric_agg_var_name] = str(agg_value)
                                for recomm_timezone, recomm_data in container_data["recommendations"]["data"].items():
                                    if recomm_timezone == timezone:
                                        for recomm_engine, recomm_enginedata in recomm_data.items():
                                            for recomm_type, recomm_typedata in recomm_enginedata.items():
                                                if "config" in recomm_typedata:
                                                    for recomm_config, recomm_configmetrics in recomm_typedata["config"].items():
                                                        for recomm_resource, recomm_resourcedata in recomm_configmetrics.items():
                                                            recomm_var_name = recomm_engine + '_' + recomm_type + '_' + recomm_resource + '_' + recomm_config
                                                            recomm_dict[recomm_var_name] = str(recomm_resourcedata["amount"])
                                #print(recomm_dict)
                                kobj_dict.update(metric_dict)
                                kobj_dict.update(recomm_dict)
                                writer.writerow(kobj_dict)
        # Sort the data in chronological order of timezone
        with open('experimentMetrics.csv', 'r') as csvfile:
            reader = csv.DictReader(csvfile)
            Edata = list(reader)
        data_sorted = sorted(Edata, key=lambda x: x['timezone'])
        
        # Write the sorted data back to the CSV file
        with open('experimentOutput.csv', 'a', newline='') as csvfile:
            fieldnames = reader.fieldnames
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(data_sorted)

