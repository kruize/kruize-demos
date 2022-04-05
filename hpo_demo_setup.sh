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

# Default cluster
CLUSTER_TYPE="native"

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
#   Cleanup Autotune git Repos
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
		if [ ${CLUSTER_TYPE} == "native" ]; then
			echo
			echo "Starting hpo with  ./deploy_hpo.sh -c ${CLUSTER_TYPE}"
			echo
			./deploy_hpo.sh -c ${CLUSTER_TYPE} &
			check_err "ERROR: HPO failed to start, exiting"
		else
			echo
			echo "Starting hpo with  ./deploy_hpo.sh -c ${CLUSTER_TYPE} -h ${HPO_DOCKER_IMAGE}"
			echo

			./deploy_hpo.sh -c ${CLUSTER_TYPE} -h ${HPO_DOCKER_IMAGE} &
			check_err "ERROR: HPO failed to start, exiting"
		fi
	popd >/dev/null
	echo "#######################################"
	echo
}

###########################################
#   Start HPO Experiments
###########################################
function hpo_experiments() {

	## TODO : Get experiment_id from search_space

	echo "#######################################"
	echo "Start a new experiment with search space json"
	## Step 1 : Start a new experiment with provided search space.
	## TODO : Check if searchspace is empty
	exp_json=$( cat "hpo_helpers/search_space.json" )
	curl  -v -s -H 'Content-Type: application/json' http://localhost:8085/experiment_trials -d '{ "operation": "EXP_TRIAL_GENERATE_NEW",  "search_space": '"${exp_json}"'}'
	check_err "Error: Creating the new experiment failed."

	## Looping through trials of an experiment
	for (( i=0 ; i<${N_TRIALS} ; i++ ))
	do
		## Step 2: Get the HPO config from HPOaaS
		echo "#######################################"
        	echo "Generate the config for trial ${i}"
		sleep 10
		HPO_CONFIG=$(curl -H 'Accept: application/json' 'http://localhost:8085/experiment_trials?experiment_id=a123&trial_number='"${i}")
		echo ${HPO_CONFIG}
		if [[ ${HPO_CONFIG} != -1 ]]; then
			echo "${HPO_CONFIG}" > hpo_config.json
		else
			check_err "Error: Issue generating the configuration from HPO."
		fi

		## Step 3: Run the benchmark with HPO config.
		echo "#######################################"
	        echo "Run the benchmark for trial ${i}"
		#BENCHMARK_OUTPUT=$(./runbenchmark.sh "${HPO_CONFIG}")
		BENCHMARK_OUTPUT="Objfunc_result=0.007914818407446147 Benchmark_status=success"
		echo ${BENCHMARK_OUTPUT}
		obj_result=$(echo ${BENCHMARK_OUTPUT} | cut -d "=" -f2 | cut -d " " -f1)
		trial_state=$(echo ${BENCHMARK_OUTPUT} | cut -d "=" -f3 | cut -d " " -f1)
		if [[ ${obj_result} == "" || ${trial_state} == "" ]]; then
			obj_result=0
			trial_state="prune"
		fi
		### Add the HPO config and output data from benchmark of all trials into single csv
		python3.6 -c "import hpo_helpers.utils; hpo_helpers.utils.hpoconfig2csv(\"hpo_config.json\",\"output.csv\",\"trials-output.csv\",\"${i}\")"

		## Step 4: Send the results of benchmark to HPOaaS
		echo "#######################################"
        	echo "Send the benchmark results for trial ${i}"
		curl  -Ss -H 'Content-Type: application/json' http://localhost:8085/experiment_trials -d '{"experiment_id" : "a123", "trial_number": '"${i}"', "trial_result": "'"${trial_state}"'", "result_value_type": "double", "result_value": '"${obj_result}"', "operation" : "EXP_TRIAL_RESULT"}'
		check_err "ERROR: Sending the results to HPO failed."

		sleep 5
		## Step 5 : Generate a subsequent trial
		echo "#######################################"
	        echo "Generate subsequent trial of ${i}"
		curl  -Ss -H 'Content-Type: application/json' http://localhost:8085/experiment_trials -d '{"experiment_id" : "a123", "operation" : "EXP_TRIAL_GENERATE_SUBSEQUENT"}'
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
	sleep 20
	if [ ${EXPERIMENT_START} -eq 1 ]; then
		hpo_experiments
	fi
	echo
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! HPO demo setup took ${elapsed_time} seconds"
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

# By default we start the demo and dont expose prometheus port
hpo_restart=0
start_demo=1
HPO_DOCKER_IMAGE=""
EXPERIMENT_START=1
# Iterate through the commandline options
while getopts di:o:prst gopts
do
	case "${gopts}" in
		d)
			EXPERIMENT_START=0
			;;
		h)
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
		*)
			usage
	esac
done

if [ ${start_demo} -eq 1 ]; then
	hpo_start
else
	hpo_terminate
fi
