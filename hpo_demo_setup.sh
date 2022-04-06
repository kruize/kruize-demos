#!/bin/bash
#
# Copyright (c) 2020, 2022 Red Hat, IBM Corporation and others.
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

# Default docker image repos
HPO_DOCKER_REPO="docker.io/kruize/hpo"
HPO_VERSION="0.01"

# Default cluster
CLUSTER_TYPE="native"
PY_CMD="python3.6"
LOGFILE="${PWD}/hpo.log"

function usage() {
	echo "Usage: $0 [-s|-t] [-d] [-i hpo-image] [-r] [-c cluster-type]"
	echo "s = start (default), t = terminate"
	echo "r = restart hpo only"
	echo "d = Don't start experiments"
	echo "p = expose prometheus port"
	exit 1
}

# get date in format
function get_date() {
	date "+%Y-%m-%d %H:%M:%S"
}

function time_diff() {
	ssec=`date --utc --date "$1" +%s`
	esec=`date --utc --date "$2" +%s`

	diffsec=$(($esec-$ssec))
	echo $diffsec
}

function check_err() {
	err=$?
	if [ ${err} -ne 0 ]; then
		echo "$*"
		exit 1
	fi
}

###########################################
#   Clone HPO git Repos
###########################################
function clone_repos() {
	echo
	echo "#######################################"
	echo "1. Cloning hpo git repos"
	if [ ! -d hpo ]; then
		git clone git@github.com:kruize/hpo.git 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kruize/hpo.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kruize/hpo failed."
	fi

	if [ ! -d benchmarks ]; then
		git clone git@github.com:kruize/benchmarks.git 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kruize/benchmarks.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kruize/benchmarks failed."
	fi
	echo "done"
	echo "#######################################"
	echo
}

###########################################
#   Cleanup HPO git Repos
###########################################
function delete_repos() {
	echo "1. Delete hpo and benchmarks git repos"
	rm -rf hpo benchmarks
}

###########################################
#   Start HPO
###########################################
function hpo_install() {
	echo
	echo "#######################################"
	echo "6. Start HPO"
	if [ ! -d hpo ]; then
		echo "ERROR: hpo dir not found."
		if [ ${hpo_restart} -eq 1 ]; then
			echo "ERROR: HPO not running. Wrong use of restart command"
		fi
		exit -1
	fi
	pushd hpo >/dev/null
		if [ -z "${HPO_DOCKER_IMAGE}" ]; then
			HPO_DOCKER_IMAGE=${HPO_DOCKER_REPO}:${HPO_VERSION}
		fi
		if [[ ${CLUSTER_TYPE} == "native" ]]; then
			echo
			echo "Starting hpo with  ./deploy_hpo.sh -c ${CLUSTER_TYPE}"
			echo
			./deploy_hpo.sh -c ${CLUSTER_TYPE} >> ${LOGFILE}  &
			#check_err "ERROR: HPO failed to start, exiting"
		else
			echo
			echo "Starting hpo with  ./deploy_hpo.sh -c ${CLUSTER_TYPE} -h ${HPO_DOCKER_IMAGE}"
			echo

			./deploy_hpo.sh -c "${CLUSTER_TYPE}" -h "${HPO_DOCKER_IMAGE}"
			#check_err "ERROR: HPO failed to start, exiting"
		fi
	popd >/dev/null
	echo "#######################################"
	echo
}

###########################################
#   Start HPO Experiments
###########################################
function hpo_experiments() {

	SEARCHSPACE_JSON="hpo_helpers/search_space.json"
	URL="http://localhost:8085"
	## TODO : Add check to eid
	eid=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.getexperimentid(\"${SEARCHSPACE_JSON}\")")
	exp_output="experiment-output.csv"

	##TODO : Delete the old logs if any before starting the experiment

	echo "#######################################"
	echo "Start a new experiment with search space json"
	## Step 1 : Start a new experiment with provided search space.
	exp_json=$( cat ${SEARCHSPACE_JSON} )
	if [[ ${exp_json} != "" ]]; then
		curl -Ss -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{ "operation": "EXP_TRIAL_GENERATE_NEW",  "search_space": '"${exp_json}"'}'
		check_err "Error: Creating the new experiment failed."
	else
		check_err "Error: Searchspace is empty"
	fi

	## Looping through trials of an experiment
	for (( i=0 ; i<${N_TRIALS} ; i++ ))
	do
		## Step 2: Get the HPO config from HPOaaS
		echo "#######################################"
        	echo "Generate the config for trial ${i}"
		sleep 2
		HPO_CONFIG=$(curl -Ss -H 'Accept: application/json' "${URL}"'/experiment_trials?experiment_id='"${eid}"'&trial_number='"${i}")
		#echo ${HPO_CONFIG}
		if [[ ${HPO_CONFIG} != -1 ]]; then
			echo "${HPO_CONFIG}" > hpo_config.json
		else
			check_err "Error: Issue generating the configuration from HPO."
		fi

		## Step 3: Run the benchmark with HPO config.
		echo "#######################################"
	        echo "Run the benchmark for trial ${i}"
		BENCHMARK_OUTPUT=$(./hpo_helpers/runbenchmark.sh ${SEARCHSPACE_JSON})
		#BENCHMARK_OUTPUT="Objfunc_result=0.007914818407446147 Benchmark_status=prune"
		echo ${BENCHMARK_OUTPUT}
		obj_result=$(echo ${BENCHMARK_OUTPUT} | cut -d "=" -f2 | cut -d " " -f1)
		trial_state=$(echo ${BENCHMARK_OUTPUT} | cut -d "=" -f3 | cut -d " " -f1)
		if [[ ${obj_result} == "" || ${trial_state} == "" ]]; then
			obj_result=0
			trial_state="prune"
		fi
		### Add the HPO config and output data from benchmark of all trials into single csv
		${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.hpoconfig2csv(\"hpo_config.json\",\"output.csv\",\"${exp_output}\",\"${i}\")"

		## Step 4: Send the results of benchmark to HPOaaS
		echo "#######################################"
        	echo "Send the benchmark results for trial ${i}"
		curl  -Ss -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{"experiment_id" : "'"${eid}"'", "trial_number": '"${i}"', "trial_result": "'"${trial_state}"'", "result_value_type": "double", "result_value": '"${obj_result}"', "operation" : "EXP_TRIAL_RESULT"}'
		check_err "ERROR: Sending the results to HPO failed."

		sleep 5
		## Step 5 : Generate a subsequent trial
		echo "#######################################"
	        echo "Generate subsequent trial of ${i}"
		curl  -Ss -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{"experiment_id" : "'"${eid}"'", "operation" : "EXP_TRIAL_GENERATE_SUBSEQUENT"}'
		check_err "ERROR: Generating the subsequent trial failed."
	done

	echo "#######################################"
	echo " Experiment complete"
	echo

}

function hpo_start() {
	
	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#        HPO Demo Setup          #"
	echo "#######################################"
	echo

	if [ ${hpo_restart} -eq 0 ]; then
		clone_repos
	fi
	hpo_install
	sleep 10
	if [ ${EXPERIMENT_START} -eq 1 ]; then
		hpo_experiments
	fi
	echo
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! HPO demo setup took ${elapsed_time} seconds"
	echo
	echo "Look into ${exp_output} for configuration and results of all trials"
	echo

}

function hpo_terminate() {
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#       HPO Demo Terminate       #"
	echo "#######################################"
	echo
	pushd hpo >/dev/null
                ./deploy_hpo.sh -t -c ${CLUSTER_TYPE}
		check_err "ERROR: Failed to terminate hpo"

		## Only for now as deploy script doesn't kill the service.
		ps -ef | grep service.py | grep -v grep | awk '{print $2}' | xargs kill -9
        popd >/dev/null
	delete_repos
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! HPO demo cleanup took ${elapsed_time} seconds"
	echo
}

# By default we start the demo and experiment
hpo_restart=0
start_demo=1
HPO_DOCKER_IMAGE=""
EXPERIMENT_START=1
# Iterate through the commandline options
while getopts di:o:c:rst gopts
do
	case "${gopts}" in
		d)
			EXPERIMENT_START=0
			;;
		i)
			HPO_DOCKER_IMAGE="${OPTARG}"
			;;
		r)
			hpo_restart=1
			;;
		s)
			start_demo=1
			;;
		t)
			start_demo=0
			;;
		c)
			CLUSTER_TYPE="${OPTARG}"
			;;
		*)
			usage
	esac
done

if [ ${start_demo} -eq 1 ]; then
	hpo_start
else
	hpo_terminate
fi
