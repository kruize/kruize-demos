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
#echo "${HPO_CONFIG}" > hpo_config.json

envoptions=`python3.6 -c "import utils; utils.convert2envoptions(\"hpo_config.json\")"`

envlist=()
IFS=,
for val in $envoptions;
do
envitem=$(echo "$val" | tr -dc '[:alnum:]-.:+\n\r\ \=' )
envlist+=( ${envitem} )
done

cpu_request=${envlist[0]}
memory_request=`echo ${envlist[1]} | sed -e 's/^[[:space:]]*//'`
envoptions="${envlist[2]}"

#echo ${cpu_request}
#echo ${memory_request}
#echo ${envoptions}

BENCHMARK_NAME="techempower"
## Clone repos
#rm -rf benchmarks
#git clone https://github.com/kusumachalasani/benchmarks.git -b tfb_p

if [[ ${BENCHMARK_NAME} == "techempower" ]]; then

	CLUSTER_TYPE="minikube"
	BENCHMARK_SERVER="localhost"
	RESULTS_DIR="results"
	TFB_IMAGE="kusumach/tfb-qrh:1.13.2.F_mm_p"
	DB_TYPE="docker"
	DURATION="60"
	WARMUPS=1
	MEASURES=3
	SERVER_INSTANCES=1
	ITERATIONS=1
	NAMESPACE="default"
	THREADS="40"
	CONNECTIONS="512"

	./benchmarks/techempower/scripts/perf/tfb-run.sh --clustertype=${CLUSTER_TYPE} -s ${BENCHMARK_SERVER} -e ${RESULTS_DIR} -g ${TFB_IMAGE} --dbtype=${DB_TYPE} --dbhost=${DB_HOST} -r -d ${DURATION} -w ${WARMUPS} -m ${MEASURES} -i ${SERVER_INSTANCES} --iter=${ITERATIONS} -n ${NAMESPACE} -t ${THREADS} --connection=${CONNECTIONS} --cpureq=${cpu_request} --memreq=${memory_request}M --cpulim=${cpu_request} --memlim=${memory_request}M --envoptions="${envoptions}"  > benchmark.log

	RES_DIR=`ls -td -- ./benchmarks/techempower/results/*/ | head -n1 `
	is_failed=$( echo $BENCHMARK_OUTPUT | grep "failed")

	if [[ -f "${RES_DIR}/output.csv" ]]; then
		## Copy the output.csv into current directory
		rm -rf output.csv
		cp -r ${RES_DIR}/output.csv .

		## TO DO : Make it better ###
		## Format csv file
		sed -i 's/\t/,/g' output.csv
		sed -i 's/ , /,/g' output.csv 
		sed -i 's/, /,/g' output.csv
		sed -i 's/ ,/,/g' output.csv
	# cat testfile | sed -r ‘s/\s+//g’
		objfunc_result=`python3.6 -c "import utils; utils.calcobj(\"search_space.json\",\"output.csv\")"`
	
		if [[ ${objfunc_result} != "" ]]; then
			benchmark_status="success"
		else
			benchmark_status="prune"
		fi
	else
		benchmark_status="prune"
	fi

	if [[ ${benchmark_status} == "prune" ]];then
		objfunc_result=0
	fi
fi

### Append output.csv into single file
python3.6 -c "import utils; utils.alltrialsoutput(\"output.csv\",\"trials-output.csv\","1")"


echo "Objfunc_result=${objfunc_result}"
echo "Benchmark_status=${benchmark_status}"
