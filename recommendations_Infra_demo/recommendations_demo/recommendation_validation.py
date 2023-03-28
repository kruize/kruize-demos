import pandas as pd
import json
import csv
import sys

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
                        for duration_type in container["recommendations"]["data"][time_zone]["duration_based"]:
                            recommendations = container["recommendations"]["data"][time_zone]
                            if "config" in recommendations["duration_based"][duration_type]:
                                cpu_limits_json = round(recommendations["duration_based"][duration_type]["config"]["limits"]["cpu"]["amount"], 4)
                                memory_limits_json = round(recommendations["duration_based"][duration_type]["config"]["limits"]["memory"]["amount"], 4)
                                cpu_requests_json = round(recommendations["duration_based"][duration_type]["config"]["requests"]["cpu"]["amount"], 4)
                                memory_requests_json = round(recommendations["duration_based"][duration_type]["config"]["requests"]["memory"]["amount"], 4)

                                writer.writerow([cluster_json, exp_name_json, container_json, time_zone, duration_type, cpu_requests_json, memory_requests_json, cpu_limits_json, memory_limits_json])


def create_recomm_csv():
    # Open a CSV file for writing
    with open('recommendationsOutput.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        # Write the headers to the CSV file
        writer.writerow(['cluster_name', 'experiment_name', 'container_name', 'time_zone', 'duration_type','cpu_requests' , 'memory_requests' , 'cpu_limits', 'memory_limits'])

def getUniquek8Objects(inputcsvfile):
    column_name = 'k8ObjectName'
    # Read the CSV file and get the unique values of the specified column
    unique_values = set()
    
    with open(inputcsvfile, 'r') as csv_file:
        csv_reader = csv.DictReader(csv_file)
        for row in csv_reader:
            unique_values.add(row[column_name])
            
    return unique_values
}

