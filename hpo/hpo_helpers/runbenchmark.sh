#!/bin/bash
#
# Copyright (c) 2021, 2022 Red Hat, IBM Corporation and others.
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
#########################################################################################
#    This script is to run the benchmark as part of trial in an experiment.             #
#    All the tunables configuration from optuna are inputs to benchmark.                #
#    This script has only techempower as the benchmark.                                 #
#                                                                                       #
#########################################################################################

HPO_CONFIG=$1
SEARCHSPACE_JSON=$2
TRIAL=$3
CLUSTER_TYPE=$4
BENCHMARK_SERVER=$5
BENCHMARK_NAME=$6
BENCHMARK_RUN_THRU=$7
JENKINS_MACHINE_NAME=$8
JENKINS_EXPOSED_PORT=${9}
JENKINS_SETUP_JOB=${10}
JENKINS_SETUP_TOKEN=${11}
JENKINS_GIT_REPO_COMMIT=${12}
HORREUM=${13}
PY_CMD="python3"
LOGFILE="${PWD}/hpo.log"
BENCHMARK_LOGFILE="${PWD}/benchmark.log"
HPO_RESULTS_DIR="${PWD}/results"

cpu_request=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.get_tunablevalue(\"hpo_config.json\", \"cpuRequest\")")
memory_request=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.get_tunablevalue(\"hpo_config.json\", \"memoryRequest\")")
jdkoptions=$(${PY_CMD} -c "import hpo_helpers.getenvoptions; hpo_helpers.getenvoptions.get_jdkoptions(\"hpo_config.json\")")
envoptions=$(${PY_CMD} -c "import hpo_helpers.getenvoptions; hpo_helpers.getenvoptions.get_envoptions(\"hpo_config.json\")")

if [[ ${BENCHMARK_RUN_THRU} == "jenkins" ]]; then
	if [[ ${BENCHMARK_NAME} == "techempower" ]]; then
		AUTOTUNE_BENCHMARKS_GIT_REPO_URL="https://github.com/kruize/benchmarks.git"
		AUTOTUNE_BENCHMARKS_GIT_REPO_BRANCH="origin/main"
		AUTOTUNE_BENCHMARKS_GIT_REPO_NAME="benchmarks"
		GIT_REPO_COMMIT="autotune-techempower"
		RESULTS_DIR="results"
		SERVER_INSTANCES="1"
		NAMESPACE="autotune-tfb"
		TFB_IMAGE="quay.io/kruize/tfb-qrh:1.13.2.F_mm_p"
		RE_DEPLOY="true"
		DB_TYPE="docker"
		DB_HOSTIP="mwperf-server"
		DURATION="60"
		WARMUPS="1"
		MEASURES="1"
		ITERATIONS="1"
		THREADS="56"
		RATE="8000"
		CONNECTION="256"
		CLEANUP="true"

		# Create an associative array to store parameters
		declare -A params
		params=(
		      ["token"]="${JENKINS_SETUP_TOKEN}"
		      ["BRANCH"]="${GIT_REPO_COMMIT}"
		      ["CLUSTER_TYPE"]="openshift"
		      ["BENCHMARK_SERVER"]="${BENCHMARK_SERVER}"
		      ["RESULTS_DIR"]="${RESULTS_DIR}"
		      ["SERVER_INSTANCES"]="${SERVER_INSTANCES}"
		      ["NAMESPACE"]="${NAMESPACE}"
		      ["TFB_IMAGE"]="${TFB_IMAGE}"
		      ["RE_DEPLOY"]="${RE_DEPLOY}"
		      ["DB_TYPE"]="${DB_TYPE}"
		      ["DB_HOSTIP"]="${DB_HOSTIP}"
		      ["DURATION"]="${DURATION}"
		      ["WARMUPS"]="${WARMUPS}"
		      ["MEASURES"]="${MEASURES}"
		      ["ITERATIONS"]="${ITERATIONS}"
		      ["THREADS"]="${THREADS}"
		      ["RATE"]="${RATE}"
		      ["CONNECTION"]="${CONNECTION}"
		      ["CPU_REQ"]="${cpu_request}"
		      ["MEM_REQ"]="${memory_request}"
		      ["CPU_LIM"]="${cpu_request}"
		      ["MEM_LIM"]="${memory_request}"
		      ["ENV_OPTIONS"]="${jdkoptions}"
		      ["AUTOTUNE_BENCHMARKS_GIT_REPO_URL"]="${AUTOTUNE_BENCHMARKS_GIT_REPO_URL}"
		      ["AUTOTUNE_BENCHMARKS_GIT_REPO_BRANCH"]="${AUTOTUNE_BENCHMARKS_GIT_REPO_BRANCH}"
		      ["AUTOTUNE_BENCHMARKS_GIT_REPO_NAME"]="${AUTOTUNE_BENCHMARKS_GIT_REPO_NAME}"
		      ["CLEANUP"]="${CLEANUP}"
		      #["PROV_HOST"]="${PROV_HOST}"
		      #["DB_HOST"]="${DB_HOST}"
	      )
	      # Initialize an empty string for the encoded query
	      query=""
	      # Loop through the parameters and encode each key and value
	      for key in "${!params[@]}"; do
		      encoded_key=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$key'''))")
		      encoded_value=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${params[$key]}'''))")
		      query+="${encoded_key}=${encoded_value}&"
	      done
	      # Remove the trailing '&'
	      query=${query%&}
	      jobUrl="https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/buildWithParameters?$query"
        else
	      declare -A params
	      params=(
		      ["token"]="${JENKINS_SETUP_TOKEN}"
                      ["BRANCH"]="${GIT_REPO_COMMIT}"
                      ["JVM_TUNABLES"]="${jdkoptions}"
                      ["ENV_OPTIONS"]="${envoptions}"
              )
              # Initialize an empty string for the encoded query
              query=""
              # Loop through the parameters and encode each key and value
              for key in "${!params[@]}"; do
                      encoded_key=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$key'''))")
                      encoded_value=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${params[$key]}'''))")
                      query+="${encoded_key}=${encoded_value}&"
              done
              # Remove the trailing '&'
              query=${query%&}
              jobUrl="https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/buildWithParameters?$query"
	fi

	# Print the constructed URL (for debugging)
	echo "Constructed Job URL: ${jobUrl}"
	JOB_START_TIME=$(date +%s%3N)
	JOB_COMPLETE=false
	COUNTER=0
        #result=$(curl -o /dev/null -sk -w "%{http_code}\n" "${jobUrl}")
	response=$(curl -s -k -i -w "%{http_code}\n" "${jobUrl}")
	location=$(echo "$response" | grep -i "Location:" | awk '{print $2}' | tr -d '\r')
	queueId=$(basename "$location")
	echo "queueId=${queueId}"
	TIMEOUT=6i0
	run_id=""
	START_TIME=$(date +%s)
	if [ -z "${queueId}" ]; then
		echo "Failed to retrieve queueId. Check if the job was triggered successfully."
		JOB_COMPLETE = "invalid"
	else
		while true; do
			#current_time=$(date +%s)
			#elapsed_time=$((current_time - START_TIME))
			#if [ "$elapsed_time" -ge "$TIMEOUT" ]; then
			#    echo "Timed out after 600 seconds. No Run ID available."
			    #JOB_COMPLETE = "invalid"
			#    break
			#fi
			queue_url="https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/queue/item/${queueId}/api/json"
			response=$(curl -s -k "${queue_url}")
			if [ -n "$response" ]; then
				run_id=$(echo "$response" | jq -r '.executable.number // empty')
				if [ -n "${run_id}" ]; then
					echo "run_id=${run_id}"
					break
				fi
				#sleep 1
			else
				# Check if the last job has the same queue_id
				JOB_STATUS=$(curl -sk "https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/lastBuild/api/json")
				JENKINS_RUN_ID=$(echo "$JOB_STATUS" | jq -r '.id')
				JENKINS_QUEUE_ID=$(echo "$JOB_STATUS" | jq -r '.queueId')
				if [[ ${JENKINS_QUEUE_ID} == ${queueId} ]]; then
					echo "run_id=${JENKINS_RUN_ID}"
				else
					echo "Couldn't find the run_id for queue_id=${queueId}"
					JOB_COMPLETE = "invalid"
				fi
				break
			fi
		done
	fi

	while [[ "${JOB_COMPLETE}" == false ]]; do
		##TODO Confirm if this the latest job triggered or using the previous one.
		JOB_STATUS=$(curl -sk "https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/${run_id}/api/json")
		# Validate JSON response
		if ! echo "$JOB_STATUS" | jq empty; then
		    echo "Error: Invalid JSON received"
		    echo "Response: $JOB_STATUS"
		fi
		JOB_TIMESTAMP=$(echo "$JOB_STATUS" | jq -r '.timestamp // 0')
		JOB_DURATION=$(echo "$JOB_STATUS" | jq -r '.duration // 0')
		JOB_RESULT=$(echo "$JOB_STATUS" | jq -r '.result // "UNKNOWN"')
		if [[ "$JOB_RESULT" == "SUCCESS" ]]; then
			JOB_COMPLETE=true
                        break
		elif [[ "$JOB_RESULT" == "FAILURE" ]]; then
			break
		fi
		#Commenting out timeout for the benchmark job
		#if [[ $((JOB_TIMESTAMP + JOB_DURATION)) -gt "${JOBSTART_TIME}" ]] && [[ "$JOB_RESULT" == "SUCCESS" ]]; then
		#	JOB_COMPLETE=true
		#	break
		#fi
		#if [[ $((JOB_TIMESTAMP + JOB_DURATION)) -gt "$START_TIME" ]] && [[ "$JOB_RESULT" == "FAILURE" ]]; then
		#	break
		#fi
		#COUNTER=$((COUNTER + 1))
		#if [ "$COUNTER" -ge "$STARTUP_TIMEOUT" ]; then
		#	break
		#fi
		sleep 5
	done

	if [[ ${JOB_COMPLETE} == true ]]; then
		if [[ ${BENCHMARK_NAME} == "techempower" ]]; then
			curl -ks https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/${run_id}/artifact/run/${PROV_HOST}/output.csv > output.csv
			## Format csv file
			sed -i 's/[[:blank:]]//g' output.csv
			## Calculate objective function result value
			objfunc_result=`${PY_CMD} -c "import hpo_helpers.getobjfuncresult; hpo_helpers.getobjfuncresult.calcobj(\"${SEARCHSPACE_JSON}\", \"output.csv\", \"${OBJFUNC_VARIABLES}\")"`
		else
			# Get horreum id
			HORREUM_RUNID=$(curl -s "https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/${run_id}/consoleText" | grep "Uploaded run ID" | awk -F ': ' '{print $2}')
			#consoleFull" | grep "Uploaded run ID" | awk '{print $5}')
			if [ -z "${HORREUM_RUNID}" ]; then
				# Try out one more time as the job is success
				echo "Trying out one more time to get the horreum_runid as it was empty even after job is successful"
				sleep 5
				HORREUM_RUNID=$(curl -s "https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/${run_id}/consoleFull" | grep "Uploaded run ID" | awk '{print $5}')
			fi
			if [ -n "${HORREUM_RUNID}" ]; then
				curl -s "https://${HORREUM}/api/run/${HORREUM_RUNID}/labelValues" | jq -r . > output.json
				if cat output.json | jq -e '.[0].values == {}' > /dev/null; then
					# Sleep for 10 seconds and try again as the values are empty
					sleep 10
					curl -s "https://${HORREUM}/api/run/${HORREUM_RUNID}/labelValues" | jq -r . > output.json
				fi
				cp output.json ${HPO_RESULTS_DIR}/trial-${TRIAL}_run-${run_id}_horreum-${HORREUM_RUNID}.json
			fi
			echo "horreumID=${HORREUM_RUNID}"

			## Calculate objective function result value
			objfunc_result=`${PY_CMD} -c "import hpo_helpers.getobjfuncresult; hpo_helpers.getobjfuncresult.calcobj(\"${SEARCHSPACE_JSON}\", \"output.json\", \"${OBJFUNC_VARIABLES}\")"`
			#Create a csv with benchmark data to append
			python3 -c "import hpo_helpers.json2csv; hpo_helpers.json2csv.horreumjson2csv(\"output.json\", \"output.csv\",\"objfn_result\", \"${objfunc_result}\")"

		fi
		if [[ ${objfunc_result} != "-1" ]]; then
			benchmark_status="success"
		else
			benchmark_status="failure"
			objfunc_result=0
			echo "Error calculating the objective function result value" >> ${LOGFILE}
		fi
	else
		benchmark_status="failure"
		objfunc_result=0
	fi
	### Add the HPO config and output data from benchmark of all trials into single csv
	${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.merge_hpoconfig_benchoutput(\"hpo_config.json\",\"output.csv\",\"jenkins-trial-output.csv\",\"${TRIAL}\")"
	${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.combine_csvs(\"jenkins-trial-output.csv\", \"experiment-output.csv\")"
	rm -rf output.csv output.json jenkins-trial-output.csv
	cp experiment-output.csv ${HPO_RESULTS_DIR}/experiment-output.csv
elif [[ ${BENCHMARK_RUN_THRU} == "standalone" ]]; then
	if [[ ${BENCHMARK_NAME} == "techempower" ]]; then

		## HEADER of techempower benchmark output.
		# headerlist = {'INSTANCES','THROUGHPUT_RATE_3m','RESPONSE_TIME_RATE_3m','MAX_RESPONSE_TIME','RESPONSE_TIME_50p','RESPONSE_TIME_95p','RESPONSE_TIME_97p','RESPONSE_TIME_99p','RESPONSE_TIME_99.9p','RESPONSE_TIME_99.99p','RESPONSE_TIME_99.999p','RESPONSE_TIME_100p','CPU_USAGE','MEM_USAGE','CPU_MIN','CPU_MAX','MEM_MIN','MEM_MAX','THRPT_PROM_CI','RSPTIME_PROM_CI','THROUGHPUT_WRK','RESPONSETIME_WRK','RESPONSETIME_MAX_WRK','RESPONSETIME_STDEV_WRK','WEB_ERRORS','THRPT_WRK_CI','RSPTIME_WRK_CI','DEPLOYMENT_NAME','NAMESPACE','IMAGE_NAME','CONTAINER_NAME'}

		OBJFUNC_VARIABLES="THROUGHPUT_RATE_3m,RESPONSE_TIME_RATE_3m,MAX_RESPONSE_TIME"
		RESULTS_DIR="results"
		TFB_IMAGE="kruize/tfb-qrh:1.13.2.F_mm_p"
		DB_TYPE="docker"
		DURATION=60
		WARMUPS=0
		MEASURES=1
		SERVER_INSTANCES=1
		ITERATIONS=1
		NAMESPACE="default"
		THREADS="3"
		CONNECTIONS="52"

		./benchmarks/techempower/scripts/perf/tfb-run.sh --clustertype=${CLUSTER_TYPE} -s ${BENCHMARK_SERVER} -e ${RESULTS_DIR} -g ${TFB_IMAGE} --dbtype=${DB_TYPE} --dbhost=${DB_HOST} -r -d ${DURATION} -w ${WARMUPS} -m ${MEASURES} -i ${SERVER_INSTANCES} --iter=${ITERATIONS} -n ${NAMESPACE} -t ${THREADS} --connection=${CONNECTIONS} --cpureq=${cpu_request} --memreq=${memory_request}M --cpulim=${cpu_request} --memlim=${memory_request}M --envoptions="${envoptions}" >& ${BENCHMARK_LOGFILE}

		RES_DIR=`ls -td -- ./benchmarks/techempower/results/*/ | head -n1 `
		if [[ -f "${RES_DIR}/output.csv" ]]; then
			## Copy the output.csv into current directory
			cp -r ${RES_DIR}/output.csv .
			cat ${RES_DIR}/../../setup.log >> ${BENCHMARK_LOGFILE}
			## Format csv file
			sed -i 's/[[:blank:]]//g' output.csv
			## Calculate objective function result value
			objfunc_result=`${PY_CMD} -c "import hpo_helpers.getobjfuncresult; hpo_helpers.getobjfuncresult.calcobj(\"${SEARCHSPACE_JSON}\", \"output.csv\", \"${OBJFUNC_VARIABLES}\")"`
			echo "$objfunc_result"
	
			if [[ ${objfunc_result} != "-1" ]]; then
				benchmark_status="success"
			else
				benchmark_status="failure"
				echo "Error calculating the objective function result value" >> ${LOGFILE}
			fi
		else
			benchmark_status="failure"
		fi

		if [[ ${benchmark_status} == "failure" ]];then
			objfunc_result=0
		fi
		### Add the HPO config and output data from benchmark of all trials into single csv
	        ${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.merge_hpoconfig_benchoutput(\"hpo_config.json\",\"output.csv\",\"experiment-output.csv\",\"${TRIAL}\")"

		## Remove the benchmark output file which is copied.
		rm -rf output.csv

	else
		benchmark_status="failure"
	        objfunc_result=0

	fi
fi

echo "Objfunc_result=${objfunc_result}"
echo "Benchmark_status=${benchmark_status}"
