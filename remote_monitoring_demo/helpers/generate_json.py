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

    print(result_json)
    print(data_csvfile)
    input_json = open(result_json, "r")
    data = json.loads(input_json.read())

    json_dir = "./result_jsons"
    os.mkdir(json_dir)
    with open(data_csvfile, 'r', newline='') as csvfile:
        reader = csv.DictReader(csvfile, delimiter=',')

        print(reader)

        j = 1
        i = 1 
        n = 1
        single_row_data = []
        complete_data = []

        mebibyte = 1048576

        for row in reader:
            container_metrics = data[0]["kubernetes_objects"][0]["containers"][0]["metrics"][0]

            # Update cpu metrics
            if container_metrics["name"] == "cpuRequest":
                container_metrics["results"]["aggregation_info"]["sum"] = float(row["cpu_request_sum_container"])
                container_metrics["results"]["aggregation_info"]["avg"] = float(row["cpu_request_avg_container"])

            if container_metrics["name"] == "cpuLimit":
                container_metrics["results"]["aggregation_info"]["sum"] = float(row["cpu_limit_sum_container"])
                container_metrics["results"]["aggregation_info"]["avg"] = float(row["cpu_limit_avg_container"])

            if container_metrics["name"] == "cpuUsage":
                container_metrics["results"]["aggregation_info"]["min"] = float(row["cpu_usage_min_container"])
                container_metrics["results"]["aggregation_info"]["avg"] = float(row["cpu_usage_avg_container"])
                container_metrics["results"]["aggregation_info"]["max"] = float(row["cpu_usage_max_container"])
                container_metrics["results"]["aggregation_info"]["sum"] = float(row["cpu_usage_sum_container"])

            if container_metrics["name"] == "cpuThrottle":
                container_metrics["results"]["aggregation_info"]["avg"] = float(row["cpu_throttle_avg_container"])
                container_metrics["results"]["aggregation_info"]["sum"] = float(row["cpu_throttle_sum_container"])
                container_metrics["results"]["aggregation_info"]["max"] = float(row["cpu_throttle_max_container"])

            # Update memory metrics
            if container_metrics["name"] == "memoryRequest":
                container_metrics["results"]["aggregation_info"]["sum"] = float(row["mem_request_sum_container"])/mebibyte
                container_metrics["results"]["aggregation_info"]["avg"] = float(row["mem_request_avg_container"])/mebibyte

            if container_metrics["name"] == "memoryLimit":
                container_metrics["results"]["aggregation_info"]["sum"] = float(row["mem_limit_sum_container"])/mebibyte
                container_metrics["results"]["aggregation_info"]["avg"] = float(row["mem_limit_avg_container"])/mebibyte

            if container_metrics["name"] == "memoryUsage":
                container_metrics["results"]["aggregation_info"]["min"] = float(row["mem_usage_min_container"])/mebibyte
                container_metrics["results"]["aggregation_info"]["avg"] = float(row["mem_usage_avg_container"])/mebibyte
                container_metrics["results"]["aggregation_info"]["max"] = float(row["mem_usage_max_container"])/mebibyte
                container_metrics["results"]["aggregation_info"]["sum"] = float(row["mem_usage_sum_container"])/mebibyte
        
            if container_metrics["name"] == "memoryRSS":
                container_metrics["results"]["aggregation_info"]["min"] = float(row["mem_rss_min_container"])/mebibyte
                container_metrics["results"]["aggregation_info"]["avg"] = float(row["mem_rss_avg_container"])/mebibyte
                container_metrics["results"]["aggregation_info"]["max"] = float(row["mem_rss_max_container"])/mebibyte
                container_metrics["results"]["aggregation_info"]["sum"] = float(row["mem_rss_sum_container"])/mebibyte

            data[0]["start_timestamp"] = convert_date_format(row["start_timestamp"])
            data[0]["end_timestamp"] = convert_date_format(row["end_timestamp"])

            single_row_data.append(data[0])

            if i % n == 0:
                json_file = json_dir + "/result_" + str(j) + ".json"
                with open(json_file, "w") as final:
                    json.dump(single_row_data, final, indent = 4)
                j += 1
                i = 1 
                single_row_data = []
            else:
                i += 1


def main(argv):
    data_csvfile="../csv_data/tfb_data.csv"

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

    result_json = "../json_files/update_results.json"
    generate_result_jsons(result_json, data_csvfile)

if __name__ == '__main__':
    main(sys.argv[1:])

