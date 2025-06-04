#!/bin/bash
#
# Copyright (c) 2023, 2023 Red Hat, IBM Corporation and others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

CLUSTER_TYPE=$1
CLUSTER_NAME=$2
current_dir="$(dirname "$0")"
SCRIPTS_REPO=$current_dir/recommendations_demo


# Run the benchmark
function run_benchmark() {
        RESULTS_DIR="results"
        TFB_IMAGE="kusumach/tfb-qrh:2.9.0.F_mm"
        DB_TYPE="docker"
        NAMESPACE="recommendation-tests"
        MODE="monitoring"
        cpu_request=3
        cpu_limit=8
        memory_request=2048
        memory_limit=4096
        BENCHMARK_LOGFILE="benchmark.log"
        DURATION=345600

	# Only until the PR #54 is merged
	# Clone benchmarks (queries has monitoring mode enabled)
	if [ ! -d benchmarks ]; then
		git clone https://github.com/kusumachalasani/benchmarks.git -b queries
	else
		pushd benchmarks >/dev/null
                # Checkout the queries branch for now
                git checkout queries
		popd >/dev/null
	fi

	# Create namespace
	kubectl create namespace ${NAMESPACE}

	# For this demo, start only TFB benchmark.
	# Command to run the TFB benchmark in monitoring mode with fixed loads
	./benchmarks/techempower/scripts/perf/tfb-run.sh --clustertype=${CLUSTER_TYPE} -s "${CLUSTER_NAME}" -e ${RESULTS_DIR} -g "${TFB_IMAGE}" --dbtype="${DB_TYPE}" --mode="${MODE}" -r -d ${DURATION} -i 1 -n "${NAMESPACE}"  --cpureq=${cpu_request} --memreq=${memory_request}M --cpulim=${cpu_limit} --memlim=${memory_limit}M --envoptions="${envoptions}" >& ${BENCHMARK_LOGFILE}  &

}


function get_tfb_results_json() {

	# Generate the json from the results of the benchmark. Uses TFB benchmark data for this demo.
	# Convert the results of last 6 hrs into json. (simulated to 1 hr for now). 
	
	# No.of lines represents the total data for that duration.
	get_lines=$1
	latest_dir=$2

	if [ ! -d "${SCRIPTS_REPO}/results" ]; then
                mkdir -p ${SCRIPTS_REPO}/results
        fi

	#Clean up if any old results exists
	rm -rf ${SCRIPTS_REPO}/results/metrics.csv

	find $latest_dir -name "*.csv" -type f -exec paste -d ',' {} + > merged.csv
	if [[ $(wc -l < merged.csv) -gt 1 ]]; then
	        { head -n 1 merged.csv; tail -n ${get_lines} merged.csv; } > ${SCRIPTS_REPO}/results/metrics.csv
        	${SCRIPTS_REPO}/replaceheaders.sh ${SCRIPTS_REPO}/results/metrics.csv
	fi

        ## Convert the csv into json
        #python3 ${SCRIPTS_REPO}/csv2json.py ${SCRIPTS_REPO}/results/metrics.csv ${SCRIPTS_REPO}/results/results.json

}

# Creates, updates and generates recommendations for an experiment
function run_monitoring_exp() {
	RESULTS_FILE=$1
	BULK_RESULTS=$2
	DAYS_DATA=$3
	EXP_TYPE=$4
	if [ -z "${EXP_TYPE}" ]; then
		EXP_TYPE="container"
	fi
	if [ -z "$DAYS_DATA" ]; then
		echo "${SCRIPTS_REPO}/recommendation_experiment.py -c ${CLUSTER_TYPE} -p \"./recommendations_demo/json_files/resource_optimization_openshift.json\" -e \"./recommendations_demo/json_files/create_exp.json\" -r  ${RESULTS_FILE} -b ${BULK_RESULTS} -t ${EXP_TYPE}"
		python3 ${SCRIPTS_REPO}/recommendation_experiment.py -c ${CLUSTER_TYPE} -p "./recommendations_demo/json_files/resource_optimization_openshift.json" -e "./recommendations_demo/json_files/create_exp.json" -r  ${RESULTS_FILE} -b ${BULK_RESULTS} -t ${EXP_TYPE}
	else
		python3 ${SCRIPTS_REPO}/recommendation_experiment.py -c ${CLUSTER_TYPE} -p "./recommendations_demo/json_files/resource_optimization_openshift.json" -e "./recommendations_demo/json_files/create_exp.json" -r  ${RESULTS_FILE} -b ${BULK_RESULTS} -d ${DAYS_DATA} -t ${EXP_TYPE}
	fi
}

# Generates recommendations along with the benchmark run in parallel
function monitoring_recommendations_demo_with_benchmark() {
	echo "Running the benchmark demo...."
	run_benchmark

	echo "Sleep for 15 mins before gathering the results"
	sleep 15m
	echo "Gathering the results..."
	# Get the latest directory in the "results" folder
	BENCHMARK_RESULTS_DIR="./benchmarks/techempower/results"
	latest_dir=$(find $BENCHMARK_RESULTS_DIR -type d -printf '%T@ %p\n' | sort -n | tail -1 | awk '{print $2}')

	## Set the medium term recommendations every 6 hours
	recommendation_type="medium_term"
	recommendation_interval="21600"
	set_recommendations "$recommendation_type" "$recommendation_interval" > setRecommendations.log 2>&1 &
	#timeout 2592000 bash -c "set_recommendations medium_term 21600" > setRecommendations.log 2>&1 &

	# Get the current time in Unix timestamp format
	now=$(date +%s)
	max_iterations_without_update=3
	interval=900
	iterations_without_update=0
	update_recommendations_interval=15mins
	recommendation_type="short_term"

	while true; do
		# Clean up any intermediate files
		rm -rf ${SCRIPTS_REPO}/results/* aggregateClusterResults.csv output cop-withobjType.csv intermediate.csv
		file="$latest_dir"/cpu_metrics.csv
		modified_time=$(date -r "$file" +%s)
		# Calculate the time difference between the current time and the file's modification time
		time_diff=$((now - modified_time))
		# Check if the time difference is less than or equal to 3600 seconds (1 hour)
		if [ $time_diff -le $interval ]; then
			echo "$file was modified in the last $interval seconds"
			# Sleep for 4m before merging the data to avoid timing issues with metrics collection
			sleep 240
			get_tfb_results_json 1 $latest_dir
			if [[ -f ${SCRIPTS_REPO}/results/metrics.csv ]]; then
				run_monitoring_exp ${SCRIPTS_REPO}/results/metrics.csv
			fi
			
		else
			echo "$file was not modified in the $interval seconds"
			# Increment the counter and exit the loop if it exceeds the threshold
                	iterations_without_update=$(( iterations_without_update + 1 ))
	                if [[ $iterations_without_update -gt $max_iterations_without_update ]]; then
        	                echo "No updates in the last 3 intervals. Exiting loop."
                	        exit 0
                	fi
		fi
		now=$(date +%s)
		sleep ${interval}s
	done
}

# Generates recommendations for a kubernetes object
function monitoring_recommendations_demo_for_k8object() {

	k8_object=$1
	k8_object_type=$2

	#Todo
	# Use cluster , namespace , object name details for monitor metrics
	# Monitor metrics for that object
	echo "Running monitor metrics..."
	monitor_metrics

	echo "Sleeping for 15 mins...."
	# Sleep for 15m to ensure it starts collecting some data.
	sleep 15m

	# Assuming, monitor_metrics collects the data in 
        #BENCHMARK_RESULTS_DIR="${SCRIPTS_REPO}/results-${k8_object_type}-${k8_object}"

        if [ ! -d "${SCRIPTS_REPO}/results" ]; then
                mkdir -p ${SCRIPTS_REPO}/results
        fi

        # Get the current time in Unix timestamp format
        now=$(date +%s)
        max_iterations_without_update=3
	# Updates the results for every 15 mins.
	interval=900
	numoflines=$((interval/900))
	iterations_without_update=0
        while true; do
		# Cleanup any previous temporary files
		rm -rf ${SCRIPTS_REPO}/results/* aggregateClusterResults.csv output cop-withobjType.csv intermediate.csv
		file=clusterresults.csv
 		intervalResultsFile=intervalResults.csv
		fileModifiedIn15mins=`find $file -type f -mmin -15`
		if [[ ${fileModifiedIn15mins} == "clusterresults.csv" ]]; then
                        echo "$file was modified in the last $interval seconds"
			echo "Aggregating the metrics from the cluster.."
			python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.aggregateWorkloads(\"$intervalResultsFile\", \"aggregateClusterResults.csv\")"
			#Get the last lines to send to Kruize updateresults API
			# Assumption only 1 application is running.
			#{ head -n 1 aggregateClusterResults.csv; tail -n ${numoflines} aggregateClusterResults.csv; } > ${SCRIPTS_REPO}/results/metrics.csv
			# Considering all apps except openshift specific
			cp aggregateClusterResults.csv ${SCRIPTS_REPO}/results/metrics.csv
			${SCRIPTS_REPO}/replaceheaders.sh ${SCRIPTS_REPO}/results/metrics.csv
				
                        run_monitoring_exp ${SCRIPTS_REPO}/results/metrics.csv
			sleep 10
			python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.get_recommondations("recommendations_data.json")'
			#python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.update_recomm_csv("recommendations_data.json")'

                else
                        echo "$file was not modified in the $interval seconds"
			# Increment the counter and exit the loop if it exceeds the threshold
			iterations_without_update=$(( iterations_without_update + 1 ))
	                if [[ $iterations_without_update -gt $max_iterations_without_update ]]; then
        	                echo "No updates in the last 3 intervals. Exiting loop."
                	        exit 0
                	fi

                fi
		echo "Sleeping for ${interval}s"
                sleep ${interval}s
        done
}

# Generates recommendations with the existing data
function monitoring_recommendations_demo_with_data() {
	BENCHMARK_RESULTS_DIR=$1
	MODE=$2
	VALIDATE=$3
	BULK_RESULTS=$4
	DAYS_DATA=$5
	EXP_TYPE=$6
	echo "Inserting the results in kruize from :  ${BENCHMARK_RESULTS_DIR}"
	if [ ! -d "${SCRIPTS_REPO}/results" ]; then
		mkdir -p ${SCRIPTS_REPO}/results
	fi
	
	for file in $(find "$BENCHMARK_RESULTS_DIR" -name "*.csv"); do
		if [[ ${VALIDATE} == "true" ]] && ([[ "$file" == *"/recommendations/"* ]] || [[ "$file" == *"/boxplots/"* ]]); then
			continue
		fi

		# Cleanup of previous temporary scripts 
		rm -rf ${SCRIPTS_REPO}/results/* metrics.csv
		if [ -s "$file" ] && [ $(wc -l < "$file") -gt 1 ]; then
			if [[ ${MODE} == "crc" ]];then
				echo "Running the results of crc mode......"
				# metrics.csv is generated with aggregated data for a k8 object.
				python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.aggregateWorkloads(\"$file\", \"metrics.csv\")"
				${SCRIPTS_REPO}/replaceheaders.sh metrics.csv
				if [ -z "$DAYS_DATA" ]; then
					run_monitoring_exp metrics.csv ${BULK_RESULTS} "" ${EXP_TYPE}
				else
					run_monitoring_exp metrics.csv ${BULK_RESULTS} ${DAYS_DATA} ${EXP_TYPE}
				fi

			else
				echo "Running the results for not crc mode"
				${SCRIPTS_REPO}/replaceheaders.sh $file
				## Convert the csv into json
				if [ -z "$DAYS_DATA" ]; then
					echo "run_monitoring_exp $file ${BULK_RESULTS} "" ${EXP_TYPE}"
					run_monitoring_exp $file ${BULK_RESULTS} "" ${EXP_TYPE}
				else
					echo "run_monitoring_exp $file ${BULK_RESULTS} ${DAYS_DATA} ${EXP_TYPE}"
                                        run_monitoring_exp $file ${BULK_RESULTS} ${DAYS_DATA} ${EXP_TYPE}
				fi
			fi
		fi
	done
	
}

function validate_experiment_recommendations() {
	BENCHMARK_RESULTS_DIR=$1
        VALIDATE=$2

        python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getExperimentNames('${CLUSTER_TYPE}')" > expoutput.txt
        names=$(cat expoutput.txt | tail -n 1)
        cleaned_names=$(echo "$names" | sed "s/\[//; s/\]//; s/'//g")
        # Convert the cleaned names into an array
        IFS=',' read -ra expnames_array <<< "$cleaned_names"
        ## Temporary code to differentiate between namespace and container experiments
        namespace_exps=()
        container_exps=()
        for str in "${expnames_array[@]}"; do
              # Count the number of pipes in the string
              pipe_count=$(echo "$str" | awk -F'|' '{print NF-1}')
              if [ "$pipe_count" -eq 1 ]; then
                      namespace_exps+=("$str")
              elif [ "$pipe_count" -gt 1 ]; then
                      container_exps+=("$str")
              fi
        done
        expnames_array=()
        if [[ ${EXP_TYPE} == "namespace" ]]; then
                expnames_array=("${namespace_exps[@]}")
        else
                expnames_array=("${container_exps[@]}")
        fi
        # Iterate over the names
        validate_status=0
        for exp_name in ${expnames_array[@]}; do
                python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getMetricsWithRecommendations('${CLUSTER_TYPE}','${exp_name}')"
                if [[ ${EXP_TYPE} == "namespace" ]]; then
                        python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.getNamespaceExperimentMetrics("metrics_recommendations_data.json")'
                else
                        python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.getExperimentMetrics("metrics_recommendations_data.json")'
                        python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.getExperimentBoxPlots("metrics_recommendations_data.json")'
                fi
                if [[ ${VALIDATE} == "true" ]]; then
                        IFS="|" read -ra parts <<< "${exp_name}"
                        recommendation_file="${parts[1]}.csv"
                        recommendation_filepath="${BENCHMARK_RESULTS_DIR}/recommendations/${recommendation_file}"
                        boxplot_filepath="${BENCHMARK_RESULTS_DIR}/boxplots/${recommendation_file}"
                        if [[ -f ${recommendation_filepath} ]]; then
                                python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.validate_experiment_recommendations_boxplots('${exp_name}', \"experimentMetrics_sorted.csv\", '${recommendation_filepath}',\"RECOMMENDATIONS\")"
                                if [[ ${EXP_TYPE} != "namespace" ]]; then
                                        python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.validate_experiment_recommendations_boxplots('${exp_name}', \"experimentPlotData_sorted.csv\", '${boxplot_filepath}',\"BOX PLOTS\")"
                                fi
                                exit_code=$?
                                validate_status=$((validate_status + exit_code))
                                echo "=================================="
                        else
                                echo "No matching recommendation output exists for $exp_name"
                                continue
                        fi
               fi
        done

	# Cleaning up all temp files
        rm -rf ${SCRIPTS_REPO}/results aggregateClusterResults.csv output cop-withobjType.csv intermediate.csv expoutput.txt experimentMetrics_temp.csv experimentMetrics_sorted.csv experimentPlotData_temp.csv experimentPlotData_sorted.csv metrics_recommendations_data.json

        if [[ ${validate_status} == 0 ]]; then
                return 0
        else
                return 1
        fi
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
	python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.validate_recomm('${recommendation_json}')'
}

# Compare the recommendations for different versions for a data
function comparing_recommendations_demo_with_data() {
	echo "comparing_recommendations_demo_with_data"
}

function monitor_metrics() {
	# Below function save data in clusterresults.csv by default. Provide -r for custom csvfileName.
	echo "Running the metrics monitor script as python3 metrics_promql.py -c ${CLUSTER_TYPE} -s ${CLUSTER_NAME}"
	nohup python3 ${SCRIPTS_REPO}/metrics_promql.py -c ${CLUSTER_TYPE} -s ${CLUSTER_NAME} &

}

# Set recommendations for the given experiment
function set_recommendations_experiment() {
	exp_name=$1
	recommendation_type=$2
	recommendation_interval=$3
	while true; do
		echo "Applying the recommendations.."
		python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getRecommendations('${CLUSTER_TYPE}','${exp_name}')"
		python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.setRecommendations("experiment_recommendations_data.json",'${recommendation_type}')'
		echo "Sleeping for ${recommendation_interval}s"
		sleep ${recommendation_interval}s
	done
}

# Set recommendations for all the experiments available
function set_recommendations() {
        recommendation_type=$1
        recommendation_interval=$2
        while true; do
		python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getExperimentNames('${CLUSTER_TYPE}')" > expoutput.txt
	        names=$(cat expoutput.txt | tail -n 1)
	        cleaned_names=$(echo "$names" | sed "s/\[//; s/\]//; s/'//g")
	        # Convert the cleaned names into an array
	        IFS=',' read -ra expnames_array <<< "$cleaned_names"
		# Iterate over the names
		for exp_name in ${expnames_array[@]}; do
			echo "Applying the recommendations for $exp_name.."
			python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getRecommendations('${CLUSTER_TYPE}','${exp_name}')"
			python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.setRecommendations('experiment_recommendations_data.json','${recommendation_type}')"
		done
		echo "Wait for ${recommendation_interval}s to set the next recommendation"
                sleep ${recommendation_interval}s
        done
}

# Get the metrics and recommendatins of all experiments
function get_metrics_recommendations() {
        python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getExperimentNames('${CLUSTER_TYPE}')" > expoutput.txt
        names=$(cat expoutput.txt | tail -n 1)
        cleaned_names=$(echo "$names" | sed "s/\[//; s/\]//; s/'//g")
        # Convert the cleaned names into an array
        IFS=',' read -ra expnames_array <<< "$cleaned_names"

        #experiment_names=$(python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getExperimentNames('${CLUSTER_TYPE}')")
        # Iterate over the names
        for exp_name in ${expnames_array[@]}; do
                echo "exp_name is $exp_name"
                python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getMetricsWithRecommendations('${CLUSTER_TYPE}','${exp_name}')"
                python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.getExperimentMetrics("metrics_recommendations_data.json")'
        done
}

function get_metrics_boxplots() {
	python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getExperimentNames('${CLUSTER_TYPE}')" > expoutput.txt
        names=$(cat expoutput.txt | tail -n 1)
        cleaned_names=$(echo "$names" | sed "s/\[//; s/\]//; s/'//g")
        # Convert the cleaned names into an array
        IFS=',' read -ra expnames_array <<< "$cleaned_names"

        # Iterate over the names
        for exp_name in ${expnames_array[@]}; do
                echo "exp_name is $exp_name"
                python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getMetricsWithRecommendations('${CLUSTER_TYPE}','${exp_name}')"
                python3 -c 'import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.getExperimentBoxPlots("metrics_recommendations_data.json")'
	done
}

function summarize_cluster_data() {
	CLUSTER_NAME=$1
	NAMESPACE_NAME=$2
	if [ -z "${CLUSTER_NAME}" ]; then
		python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.summarizeClusterData('${CLUSTER_TYPE}')"
		python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.get_cluster_data_csv('cluster','cluster_data.json','clusterData.csv')"
	elif [ -z "${NAMESPACE_NAME}" ]; then
		python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.summarizeClusterData('${CLUSTER_TYPE}','${CLUSTER_NAME}')"
		python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.get_cluster_data_csv('cluster','cluster_data.json','clusterData.csv')"
	else
		python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.summarizeClusterData('${CLUSTER_TYPE}','${CLUSTER_NAME}','${NAMESPACE_NAME}')"
		python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.get_cluster_data_csv('clusterNamespace','cluster_namespace_data.json','clusterNamespaceData.csv')"
	fi
}

function summarize_namespace_data() {
        NAMESPACE_NAME=$1
	if [ ! -z "$namespaceName" ]; then
		python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.summarizeNamespaceData('${CLUSTER_TYPE}','${NAMESPACE_NAME}')"
		python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.get_cluster_data_csv('clusterNamespace','namespace_data.json','namespaceData.csv')"
	else
		python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.summarizeNamespaceData('${CLUSTER_TYPE}')"
                python3 -c "import recommendations_demo.recommendation_validation; recommendations_demo.recommendation_validation.get_cluster_data_csv('clusterNamespace','namespace_data.json','namespaceData.csv')"

	fi
}

function summarize_all_data() {
	python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.summarizeAllData('${CLUSTER_TYPE}')"
	python3 -c "import recommendations_demo.recommendation_experiment; recommendations_demo.recommendation_experiment.getAllExperimentsRecommendations('${CLUSTER_TYPE}')"
}
