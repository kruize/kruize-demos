import csv
import json
import os
import datetime
import sys
import getopt

def convert_date_format(input_date_str):
    input_date = datetime.datetime.strptime(input_date_str, "%a %b %d %H:%M:%S UTC %Y")
    output_date_str = input_date.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    return output_date_str

def generate_result_jsons(result_json, data_csvfile):

    complete_data = []
    print(data_csvfile)
    input_json = open(result_json, "r")
    data = json.loads(input_json.read())

    json_dir = "./resource_usage_metrics_data"
    isExist = os.path.exists(json_dir)
    if not isExist:
        os.mkdir(json_dir)

    with open(data_csvfile, 'r', newline='') as csvfile:
        reader = csv.DictReader(csvfile, delimiter=',')

        print(reader)

        j = 1
        i = 1 
        n = 1
        num_res = 120

        mebibyte = 1048576

        for row in reader:
            single_row_data = []

            container_metrics = data[0]["kubernetes_objects"][0]["containers"][0]["metrics"]

            # Update cpu metrics
            if container_metrics[0]["name"] == "cpuRequest":
                container_metrics[0]["results"]["aggregation_info"]["sum"] = float(row["cpu_request_sum_container"])
                container_metrics[0]["results"]["aggregation_info"]["avg"] = float(row["cpu_request_avg_container"])

            if container_metrics[1]["name"] == "cpuLimit":
                container_metrics[1]["results"]["aggregation_info"]["sum"] = float(row["cpu_limit_sum_container"])
                container_metrics[1]["results"]["aggregation_info"]["avg"] = float(row["cpu_limit_avg_container"])

            if container_metrics[2]["name"] == "cpuUsage":
                container_metrics[2]["results"]["aggregation_info"]["min"] = float(row["cpu_usage_min_container"])
                container_metrics[2]["results"]["aggregation_info"]["avg"] = float(row["cpu_usage_avg_container"])
                container_metrics[2]["results"]["aggregation_info"]["max"] = float(row["cpu_usage_max_container"])
                container_metrics[2]["results"]["aggregation_info"]["sum"] = float(row["cpu_usage_sum_container"])

            if container_metrics[3]["name"] == "cpuThrottle":
                container_metrics[3]["results"]["aggregation_info"]["avg"] = float(row["cpu_throttle_avg_container"])
                container_metrics[3]["results"]["aggregation_info"]["sum"] = float(row["cpu_throttle_sum_container"])
                container_metrics[3]["results"]["aggregation_info"]["max"] = float(row["cpu_throttle_max_container"])

            # Update memory metrics
            if container_metrics[4]["name"] == "memoryRequest":
                container_metrics[4]["results"]["aggregation_info"]["sum"] = float(row["mem_request_sum_container"])/mebibyte
                container_metrics[4]["results"]["aggregation_info"]["avg"] = float(row["mem_request_avg_container"])/mebibyte

            if container_metrics[5]["name"] == "memoryLimit":
                container_metrics[5]["results"]["aggregation_info"]["sum"] = float(row["mem_limit_sum_container"])/mebibyte
                container_metrics[5]["results"]["aggregation_info"]["avg"] = float(row["mem_limit_avg_container"])/mebibyte

            if container_metrics[6]["name"] == "memoryUsage":
                container_metrics[6]["results"]["aggregation_info"]["min"] = float(row["mem_usage_min_container"])/mebibyte
                container_metrics[6]["results"]["aggregation_info"]["avg"] = float(row["mem_usage_avg_container"])/mebibyte
                container_metrics[6]["results"]["aggregation_info"]["max"] = float(row["mem_usage_max_container"])/mebibyte
                container_metrics[6]["results"]["aggregation_info"]["sum"] = float(row["mem_usage_sum_container"])/mebibyte
        
            if container_metrics[7]["name"] == "memoryRSS":
                container_metrics[7]["results"]["aggregation_info"]["min"] = float(row["mem_rss_min_container"])/mebibyte
                container_metrics[7]["results"]["aggregation_info"]["avg"] = float(row["mem_rss_avg_container"])/mebibyte
                container_metrics[7]["results"]["aggregation_info"]["max"] = float(row["mem_rss_max_container"])/mebibyte
                container_metrics[7]["results"]["aggregation_info"]["sum"] = float(row["mem_rss_sum_container"])/mebibyte

            data[0]["interval_start_time"] = convert_date_format(row["interval_start_time"])
            data[0]["interval_end_time"] = convert_date_format(row["interval_end_time"])

            single_row_data.append(data[0])

            json_file = json_dir + "/result_" + str(j) + ".json"
            with open(json_file, "w") as final:
                json.dump(single_row_data, final, indent = 4)
            j += 1

            json_data = json.load(open(json_file))
            complete_data.append(json_data[0])

    result_json_file = "result_complete.json"
    with open(result_json_file, "w") as final:
        json.dump(complete_data, final, indent = 4)

def main(argv):
    data_csvfile="./csv_data/metrics_15d.csv"

    try:
        opts, args = getopt.getopt(argv,"h:c:")
    except getopt.GetoptError:
        print("generate_json.py -c <csv file>")
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print("generate_json.py -c <csv file>")
            sys.exit()
        elif opt == '-c':
            data_csvfile = arg

    result_json = "./json_files/update_results.json"
    generate_result_jsons(result_json, data_csvfile)

if __name__ == '__main__':
    main(sys.argv[1:])

