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
    print(tunable_value)

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
def hpoconfig2csv(hpoconfigjson, benchmarkcsv, outputcsv, trial):
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

    ## TODO : header of benchmark data will be missing if trial 0 is pruned.
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
    
    with open(outputcsv, 'a', newline='') as f:
        output = csv.writer(f)
        if trial == "0":
            output.writerow(list1)
        output.writerow(list2)
