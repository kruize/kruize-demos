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

##TO DO: Check if minikube is running and has prometheus installed to capture the data

HPO_CONFIG=$1
SEARCHSPACE_JSON=$2
TRIAL=$3
DURATION=$4
CLUSTER_TYPE=$5
BENCHMARK_SERVER=$6

PY_CMD="python3"
LOGFILE="${PWD}/hpo.log"
BENCHMARK_NAME="techempower"
BENCHMARK_LOGFILE="${PWD}/benchmark.log"

cpu_request=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.get_tunablevalue(\"hpo_config.json\", \"cpuRequest\")")
memory_request=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.get_tunablevalue(\"hpo_config.json\", \"memoryRequest\")")
envoptions=$(${PY_CMD} -c "import hpo_helpers.getenvoptions; hpo_helpers.getenvoptions.get_envoptions(\"hpo_config.json\")")

if [[ ${BENCHMARK_NAME} == "techempower" ]]; then

	## HEADER of techempower benchmark output.
	# headerlist = {'INSTANCES','THROUGHPUT_RATE_3m','RESPONSE_TIME_RATE_3m','MAX_RESPONSE_TIME','RESPONSE_TIME_50p','RESPONSE_TIME_95p','RESPONSE_TIME_97p','RESPONSE_TIME_99p','RESPONSE_TIME_99.9p','RESPONSE_TIME_99.99p','RESPONSE_TIME_99.999p','RESPONSE_TIME_100p','CPU_USAGE','MEM_USAGE','CPU_MIN','CPU_MAX','MEM_MIN','MEM_MAX','THRPT_PROM_CI','RSPTIME_PROM_CI','THROUGHPUT_WRK','RESPONSETIME_WRK','RESPONSETIME_MAX_WRK','RESPONSETIME_STDEV_WRK','WEB_ERRORS','THRPT_WRK_CI','RSPTIME_WRK_CI','DEPLOYMENT_NAME','NAMESPACE','IMAGE_NAME','CONTAINER_NAME'}

	OBJFUNC_VARIABLES="THROUGHPUT_RATE_3m,RESPONSE_TIME_RATE_3m,MAX_RESPONSE_TIME"
	RESULTS_DIR="results"
	TFB_IMAGE="kruize/tfb-qrh:1.13.2.F_mm_p"
	DB_TYPE="docker"
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
