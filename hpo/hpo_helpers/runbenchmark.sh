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
BENCHMARK_RUN_THRU=$6

PY_CMD="python3"
LOGFILE="${PWD}/hpo.log"
BENCHMARK_NAME="techempower"
BENCHMARK_LOGFILE="${PWD}/benchmark.log"

cpu_request=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.get_tunablevalue(\"hpo_config.json\", \"cpuRequest\")")
memory_request=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.get_tunablevalue(\"hpo_config.json\", \"memoryRequest\")")
envoptions=$(${PY_CMD} -c "import hpo_helpers.getenvoptions; hpo_helpers.getenvoptions.get_envoptions(\"hpo_config.json\")")

if [[ ${BENCHMARK_NAME} == "techempower" ]] && [[ ${BENCHMARK_RUN_THRU} == "jenkins" ]]; then
	GIT_REPO_COMMIT="autotune-techempower"
	RESULTS_DIR="results"
	SERVER_INSTANCES="1"
	NAMESPACE="autotune-tfb"
	TFB_IMAGE="kh/tfb-qrh:1.13.2.F_mm_p"
	RE_DEPLOY="true"
	DB_TYPE="STANDALONE"
	DB_HOSTIP="mwperf-server"
	DURATION="60"
	WARMUPS="1"
	MEASURES="1"
	ITERATIONS="1"
	THREADS="56"
	RATE="8000"
	CONNECTION="256"
	CLEANUP="true"

	# Construct the job URL
	jobUrl="https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/buildWithParameters"
	jobUrl="${jobUrl}?token=${JENKINS_SETUP_TOKEN}"
	jobUrl="${jobUrl}&BRANCH=${GIT_REPO_COMMIT}"
	jobUrl="${jobUrl}&CLUSTER_TYPE=openshift"
	jobUrl="${jobUrl}&BENCHMARK_SERVER=${PROV_HOST}"
	jobUrl="${jobUrl}&RESULTS_DIR=${RESULTS_DIR}"
	jobUrl="${jobUrl}&SERVER_INSTANCES=${SERVER_INSTANCES}"
	jobUrl="${jobUrl}&NAMESPACE=${NAMESPACE}"
	jobUrl="${jobUrl}&TFB_IMAGE=${TFB_IMAGE}"
	jobUrl="${jobUrl}&RE_DEPLOY=${RE_DEPLOY}"
	jobUrl="${jobUrl}&DB_TYPE=${DB_TYPE}"
	jobUrl="${jobUrl}&DB_HOSTIP=${DB_HOSTIP}"
	jobUrl="${jobUrl}&DURATION=${DURATION}"
	jobUrl="${jobUrl}&WARMUPS=${WARMUPS}"
	jobUrl="${jobUrl}&MEASURES=${MEASURES}"
	jobUrl="${jobUrl}&ITERATIONS=${ITERATIONS}"
	jobUrl="${jobUrl}&THREADS=${THREADS}"
	jobUrl="${jobUrl}&RATE=${RATE}"
	jobUrl="${jobUrl}&CONNECTION=${CONNECTION}"
	jobUrl="${jobUrl}&CPU_REQ=${cpu_request}"
	jobUrl="${jobUrl}&MEM_REQ=${memory_request}"
	jobUrl="${jobUrl}&CPU_LIM=${cpu_request}"
	jobUrl="${jobUrl}&MEM_LIM=${memory_request}"
	jobUrl="${jobUrl}&ENV_OPTIONS=${envoptions}"
	jobUrl="${jobUrl}&AUTOTUNE_BENCHMARKS_GIT_REPO_URL=${AUTOTUNE_BENCHMARKS_GIT_REPO_URL}"
	jobUrl="${jobUrl}&AUTOTUNE_BENCHMARKS_GIT_REPO_BRANCH=${AUTOTUNE_BENCHMARKS_GIT_REPO_BRANCH}"
	jobUrl="${jobUrl}&AUTOTUNE_BENCHMARKS_GIT_REPO_NAME=${AUTOTUNE_BENCHMARKS_GIT_REPO_NAME}"
	jobUrl="${jobUrl}&CLEANUP=${CLEANUP}"
	jobUrl="${jobUrl}&PROV_HOST=${PROV_HOST}"
	jobUrl="${jobUrl}&DB_HOST=${DB_HOST}"

	# Print the constructed URL (for debugging)
	echo "Constructed Job URL: $jobUrl"
	JOB_START_TIME=$(date +%s%3N)
	JOB_COMPLETE=false
	COUNTER=0
	STARTUP_TIMEOUT=60
        result=$(curl -o /dev/null -sk -w "%{http_code}\n" "${jobUrl}")
	while [[ "${JOB_DONE}" == false ]]; do
		JOB_STATUS=$(curl -sk "https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/lastBuild/api/json" | jq -r '. | {timestamp, duration, result}')
		JOB_TIMESTAMP=$(echo "$JOB_STATUS" | jq -r '.timestamp')
		JOB_DURATION=$(echo "$JOB_STATUS" | jq -r '.duration')
		JOB_RESULT=$(echo "$JOB_STATUS" | jq -r '.result')
		if [ $((JOB_TIMESTAMP + JOB_DURATION)) -gt "${JOBSTART_TIME}" ] && [ "$JOB_RESULT" = "SUCCESS" ]; then
			JOB_COMPLETE=true
			break
		fi
		if [ $((JOB_TIMESTAMP + JOB_DURATION)) -gt "$START_TIME" ] && [ "$JOB_RESULT" = "FAILURE" ]; then
			break
		fi
		COUNTER=$((COUNTER + 1))
		if [ "$COUNTER" -ge "$STARTUP_TIMEOUT" ]; then
			break
		fi
		sleep 5
	done

	if [[ ${JOB_COMPLETE} == true ]]; then
		curl -ks https://${JENKINS_MACHINE_NAME}:${JENKINS_EXPOSED_PORT}/job/${JENKINS_SETUP_JOB}/lastSuccessfulBuild/artifact/run/${PROV_HOST}/output.csv > output.csv	
		## Format csv file
		sed -i 's/[[:blank:]]//g' output.csv
		## Calculate objective function result value
		objfunc_result=`${PY_CMD} -c "import hpo_helpers.getobjfuncresult; hpo_helpers.getobjfuncresult.calcobj(\"${SEARCHSPACE_JSON}\", \"output.csv\", \"${OBJFUNC_VARIABLES}\")"`
		echo "$objfunc_result"
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
	${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.hpoconfig2csv(\"hpo_config.json\",\"output.csv\",\"experiment-output.csv\",\"${TRIAL}\")"
	rm -rf output.csv
fi

if [[ ${BENCHMARK_NAME} == "techempower" ]] && [[ ${BENCHMARK_RUN_THRU} == "standalone" ]]; then

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
        ${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.hpoconfig2csv(\"hpo_config.json\",\"output.csv\",\"experiment-output.csv\",\"${TRIAL}\")"

	## Remove the benchmark output file which is copied.
	rm -rf output.csv

fi

echo "Objfunc_result=${objfunc_result}"
echo "Benchmark_status=${benchmark_status}"
