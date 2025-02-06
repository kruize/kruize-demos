import os
import json
import csv

## Get tunable values from HPO config.
## Input: hpo_config json , tunable name
## Output: tunable value 
def get_tunablevalue(hpoconfigjson, tunable_name):
    with open(hpoconfigjson) as data_file:
        sstunables = json.load(data_file)
        for st in sstunables:
            if st["tunable_name"] == tunable_name:
                tunable_value = str(st["tunable_value"])
                return tunable_value
    return None

## Get experiment_id from the searchspace
## Input: searchspacejson
## Output: experiment_id
def getexperimentid(searchspacejson):
    with open(searchspacejson) as f:
        sdata = json.load(f)
        for sd in sdata:
            ## Get experiment id
            if sd == "experiment_id":
                eid = sdata["experiment_id"]
    print(eid)

## Get experiment_name from the searchspace
## Input: searchspacejson
## Output: experiment_name
def getexperimentname(searchspacejson):
    with open(searchspacejson) as f:
        sdata = json.load(f)
        for sd in sdata:
            ## Get experiment name
            if sd == "experiment_name":
                ename = sdata["experiment_name"]
    print(ename)

## Get total_trials from searchspace
## Input: searchspacejson
## Output: total_trials
def gettrials(searchspacejson):
    with open(searchspacejson) as f:
        sdata = json.load(f)
        for sd in sdata:
            ## Get trials
            if sd == "total_trials":
                etrials = sdata["total_trials"]
    print(etrials)
    
## Appends hpoconfig and benchmarks results into single csv for all trials
## Input: hpo_config json , benchmark output csv , trial number
## Output: Output file with both hpo_config and benchmark output with trial number
## Deletes an intermediate file "intermediate.csv" used.
def merge_hpoconfig_benchoutput(hpoconfigjson, benchmarkcsv, outputcsv, trial):
    list2 = []
    list1 = []
    with open(hpoconfigjson, "r") as f:
        data = json.load(f)

    ## Uses intermediate file to append trial number
    with open("intermediate.csv", "w") as f:
        output = csv.writer(f)
        output.writerow(data[0].keys())
        for row in data:
            output.writerow(row.values())

    with open('intermediate.csv', 'r') as f:
        csv_reader = csv.reader(f, delimiter=',')
        for row in csv_reader:
            list1.append(row[0])
            list2.append(row[1])

    list1.remove("tunable_name")
    list2.remove("tunable_value")
    list1.insert(0, "Trial")
    list2.insert(0, trial)
    ## Deleting the intermediate file
    os.remove("intermediate.csv")

    ## TODO : header of benchmark data will be missing if trial 0 status is failure.
    if os.path.isfile(benchmarkcsv):
        with open(benchmarkcsv, 'r') as f:
            csv_reader = csv.DictReader(f, delimiter=',')
            header_dict = dict(list(csv_reader)[0])
            header_list = list(header_dict.keys())
            list1.extend(header_list)
        with open(benchmarkcsv, 'r') as f:
            reader = csv.reader(f, delimiter=',')
            data_list = list(reader)[1]
            list2.extend(data_list)
    
    file_mode = 'a' if os.path.exists(outputcsv) and os.stat(outputcsv).st_size > 0 else 'w'
    with open(outputcsv, file_mode, newline='') as f:
        output = csv.writer(f)
        if file_mode == 'w':
        #if trial == "0":
            output.writerow(list1)
        output.writerow(list2)

def csv2json(csv_file, json_file):
    data = []
    with open(csv_file, 'r') as csv_f:
        csv_reader = csv.DictReader(csv_f)
        for row in csv_reader:
            data.append(row)
    with open(json_file, 'w') as json_f:
        json.dump(data, json_f, ensure_ascii=False)

def combine_csvs(csv_file1, csv_file2):
    if not os.path.exists(csv_file1) and not os.path.exists(csv_file2):
        return
    if not os.path.exists(csv_file1):
        return
    json_file1 = "file1.json"
    json_file2 = "file2.json"
    csv2json(csv_file1, json_file1)
    with open(json_file1, 'r') as f1:
        data1 = json.load(f1)

    if os.path.exists(csv_file2):
        csv2json(csv_file2, json_file2)
        with open(json_file2, 'r') as f2:
            data2 = json.load(f2)
    else:
        data2 = []

    if not data2:
        with open(csv_file2, mode='w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=data1[0].keys())
            writer.writeheader()
            writer.writerows(data1)
        os.remove(json_file1)
        return

    # TODO: Good to have some order.
    headers1 = set(data1[0].keys()) if data1 else set()
    headers2 = set(data2[0].keys()) if data2 else set()
    combined_headers = list(headers1.union(headers2))

    def align_data(data, headers):
        return [
            {header: row.get(header, "") for header in headers}
            for row in data
        ]

    aligned_data1 = align_data(data1, combined_headers)
    aligned_data2 = align_data(data2, combined_headers)

    combined_data = []
    combined_data = aligned_data1 + aligned_data2

    if combined_data:
        with open(csv_file2, mode='w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=combined_data[0].keys())
            writer.writeheader()
            writer.writerows(combined_data)

    os.remove(json_file1)
    os.remove(json_file2)
