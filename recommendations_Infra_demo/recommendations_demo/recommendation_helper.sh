#!/bin/bash

CLUSTER_TYPE=$1
current_dir="$(dirname "$0")"
SCRIPTS_REPO=$current_dir/recommendations_demo

# Run the benchmark
function run_benchmark() {
	BENCHMARK_SERVER="bm.example.com"
	RESULTS_DIR="results"
	TFB_IMAGE="kusumach/tfb-qrh:2.9.0.F_mm"
	DB_TYPE="STANDALONE"
	DB_HOST="e23-h37-740xd.alias.bos.scalelab.redhat.com"
	NAMESPACE="autotune-tfb"
	MODE="monitoring"
	cpu_request=3
	cpu_limit=8
	memory_request=2048
	memory_limit=4096
	BENCHMARK_LOGFILE="benchmark.log"
	DURATION=345600
	
	# Clone benchmarks (queries has monitoring mode enabled)
	git clone https://github.com/kusumachalasani/benchmarks.git -b queries
	
	# For this demo, start only TFB benchmark.
	# Command to run the TFB benchmark in monitoring mode with fixed loads
	./benchmarks/techempower/scripts/perf/tfb-run.sh --clustertype=${CLUSTER_TYPE} -s "${BENCHMARK_SERVER}" -e ${RESULTS_DIR} -g "${TFB_IMAGE}" --dbtype="${DB_TYPE}" --dbhost="${DB_HOST}" --mode="${MODE}" -r -d ${DURATION} -i 1 -n "${NAMESPACE}"  --cpureq=${cpu_request} --memreq=${memory_request}M --cpulim=${cpu_limit} --memlim=${memory_limit}M --envoptions="${envoptions}" >& ${BENCHMARK_LOGFILE}  &

}

# Converts the results csv from benchmark into json
function get_tfb_results_json() {

	# Generate the json from the results of the benchmark. Uses TFB benchmark data for this demo.
	# Convert the results of last 6 hrs into json. (simulated to 1 hr for now). 
	
	# No.of lines represents the total data for that duration.
	get_lines=$1
	latest_dir=$2

	if [ ! -d "${SCRIPTS_REPO}/results" ]; then
                mkdir -p ${SCRIPTS_REPO}/results
        fi

	#echo "find $latest_dir -name "*.csv" -type f -exec paste -d ',' {} +"
	find $latest_dir -name "*.csv" -type f -exec paste -d ',' {} + > merged.csv
        { head -n 1 merged.csv; tail -n ${get_lines} merged.csv; } > ${SCRIPTS_REPO}/results/metrics.csv
        ${SCRIPTS_REPO}/replaceheaders.sh ${SCRIPTS_REPO}/results/metrics.csv

        ## Convert the csv into json
        python3 ${SCRIPTS_REPO}/csv2json.py ${SCRIPTS_REPO}/results/metrics.csv ${SCRIPTS_REPO}/results/results.json

}

# Creates, updates and generates recommendations for an experiment
function run_monitoring_exp() {
	resultsFile=$1
	## Generate recommendations for the csv
	python3 ${SCRIPTS_REPO}/recommendation_exp.py ./recommendations_demo/json_files/resource_optimization_openshift.json ./recommendations_demo/json_files/create_exp.json ${resultsFile}
}

# Generates recommendations along with the benchmark run in parallel
function monitoring_recommendations_demo_with_benchmark() {

        # Get the latest directory in the "results" folder
        BENCHMARK_RESULTS_DIR="./benchmarks/techempower/results"
        latest_dir=$(find $BENCHMARK_RESULTS_DIR -type d -printf '%T@ %p\n' | sort -n | tail -1 | awk '{print $2}')

	# Get the current time in Unix timestamp format
	now=$(date +%s)
	max_iterations_without_update=3
	interval=900
	while true; do
		iterations_without_update=0
		file="$latest_dir"/cpu_metrics.csv
		modified_time=$(date -r "$file" +%s)
		# Calculate the time difference between the current time and the file's modification time
		time_diff=$((now - modified_time))
		# Check if the time difference is less than or equal to 3600 seconds (1 hour)
		if [ $time_diff -le $interval ]; then
			echo "$file was modified in the last $interval seconds"
			get_tfb_results_json 4 $latest_dir
			run_monitoring_exp
			
		else
			echo "$file was not modified in the $interval seconds"
		fi
		now=$(date +%s)
		sleep ${interval}s
		# Increment the counter and exit the loop if it exceeds the threshold
		iterations_without_update=$(( iterations_without_update + 1 ))
		if [[ $iterations_without_update -gt $max_iterations_without_update ]]; then
			echo "No updates in the last 3 intervals. Exiting loop."
			exit 0
		fi
	done
}

# Generates recommendations for a kubernetes object
function monitoring_recommendations_demo_for_k8object() {

	k8_object=$1
	k8_object_type=$2

	#Todo
	# Use clsuter , namespace , object name details for monitor metrics
	# Monitor metrics for that object
	# Below function save data in clusterresults.csv
	monitor_metrics

	# Sleep for 15m to ensure it starts collecting some data.
	sleep 15m

	# Assuming, monitor_metrics collects the data in 
        #BENCHMARK_RESULTS_DIR="${SCRIPTS_REPO}/results-${k8_object_type}-${k8_object}"

        # Get the current time in Unix timestamp format
        now=$(date +%s)
        max_iterations_without_update=3
	# Updates the results for every 15 mins.
	interval=900
	numoflines = $interval / 900
        while true; do
                iterations_without_update=0
                #file="$BENCHMARK_RESULTS_DIR"/cpu_metrics.csv
		file=clusterresults.csv
                modified_time=$(date -r "$file" +%s)
                # Calculate the time difference between the current time and the file's modification time
                time_diff=$((now - modified_time))
                # Check if the time difference is less than or equal to 3600 seconds (1 hour)
                if [ $time_diff -le $interval ]; then
                        echo "$file was modified in the last $interval seconds"
			## TODO: Below aggregateWorkloadMetrics aggregates for the whole file. Instead we can do it for specific interval.	
			python3 recommendations_demo/aggregateWorkloadMetrics.py $file	
			#Get the last lines to send to Kruize updateresults API
			# Assumption only 1 application is running.
			{ head -n 1 $file; tail -n ${numoflines} $file; } > ${SCRIPTS_REPO}/results/metrics.csv
			${SCRIPTS_REPO}/replaceheaders.sh ${SCRIPTS_REPO}/results/metrics.csv
				
                        run_monitoring_exp ${SCRIPTS_REPO}/results/metrics.csv

                else
                        echo "$file was not modified in the $interval seconds"
                fi
                now=$(date +%s)
                sleep ${interval}s
                # Increment the counter and exit the loop if it exceeds the threshold
                iterations_without_update=$(( iterations_without_update + 1 ))
                if [[ $iterations_without_update -gt $max_iterations_without_update ]]; then
                        echo "No updates in the last 3 intervals. Exiting loop."
                        exit 0
                fi
        done
}

# Generates recommendations with the existing data
function monitoring_recommendations_demo_with_data() {
	#BENCHMARK_RESULTS_DIR="./tfb-results"
	BENCHMARK_RESULTS_DIR=$1
	MODE=$2
	echo "Results Dir is ... ${BENCHMARK_RESULTS_DIR}"
	echo "MODE is $MODE"
	if [ ! -d "${SCRIPTS_REPO}/results" ]; then
		mkdir -p ${SCRIPTS_REPO}/results
	fi

	# Commenting this out as we may not require now as updating multiple results are not supported.
        #split_csvs $BENCHMARK_RESULTS_DIR

	#for file in "$BENCHMARK_RESULTS_DIR"/splitfiles/*.csv; do
	for file in "$BENCHMARK_RESULTS_DIR"/*.csv; do
		echo "File is found.... $file"
		if [ -s "$file" ] && [ $(wc -l < "$file") -gt 1 ]; then
			if [ ${MODE} == "crc" ];then
				echo "Running the results of crc mode.........................."
				# metrics.csv is generated with aggregated data for a k8 object.
				python3 recommendations_demo/aggregateWorkloadMetrics.py $file
				${SCRIPTS_REPO}/replaceheaders.sh metrics.csv
				#python3 ${SCRIPTS_REPO}/csv2json.py $file ${SCRIPTS_REPO}/results/results.json
				run_monitoring_exp metrics.csv
			else
				${SCRIPTS_REPO}/replaceheaders.sh $file
				## Convert the csv into json
				#python3 ${SCRIPTS_REPO}/csv2json.py $file ${SCRIPTS_REPO}/results/results.json
				run_monitoring_exp $file
			fi
	#		validate_recommendations recommendation_data.json
			sleep 1s
		fi
	done
	validate_recommendations recommendations_data.json
}

# Split the csv data into multiple files of 6 hr data.
function split_csvs() {
	
	input_dir=$1
	input_file="${input_dir}/metrics.csv"
	output_dir="${input_dir}/splitfiles"
	rm -rf "$output_dir"
	mkdir -p "$output_dir"

	header=$(head -n 1 "$input_file")	
	lines_per_file=24

	# Split the input file into 24-line chunks(6hr data) and save each chunk as a separate CSV file
	split -a 3 -l $lines_per_file --additional-suffix=.csv <(tail -n +2 "$input_file") "${output_dir}/ITR_"

	# Loop over the output files and add the header to each file
	for file in "${output_dir}/ITR_"*.csv
	do
	    sed -i "1i$header" "$file"
	    sed -i '/^$/d' "$file"
	done
}

function validate_recommendations() {
	recommendation_json=$1
	python ${SCRIPTS_REPO}/recommendation_validation.py $recommendation_json
}

# Compare the recommendations for different versions for a data
function comparing_recommendations_demo_with_data() {
	echo "comparing_recommendations_demo_with_data"
}

function monitor_metrics() {
	#./monitor_metrics_promql.sh
	# Below function save data in clusterresults.csv by default. Provide -r for custom csvfileName.
	nohup python metrics_promql.py -c minikube -s localhost &

}

function getUniquek8Objects() {
	inputcsvfile=$1
	column_name = 'k8ObjectName'
	
	# Read the CSV file and get the unique values of the specified column
	unique_values = set()

	with open(inputcsvfile, 'r') as csv_file:
           csv_reader = csv.DictReader(csv_file)
       	   for row in csv_reader:
	      unique_values.add(row[column_name])
	      
	return unique_values
}

