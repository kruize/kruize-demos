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
PY_CMD="python3"
LOGFILE="${PWD}/hpo.log"
export N_TRIALS=3
export N_JOBS=1

function usage() {
	echo "Usage: $0 [-s|-t] [-d] [-o hpo-image] [-r] [-c cluster-type]"
	echo "s = start (default), t = terminate"
	echo "r = restart hpo only"
	echo "d = Don't start experiments"
	echo "c = supports native and docker cluster-type to start HPO service"
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

function err_exit() {
	echo "$*"
	exit 1
}

###########################################
#   Clone HPO git Repos
###########################################
function clone_repos() {
	echo
	echo "#######################################"
	echo "Cloning hpo git repos"
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
	echo "Delete hpo and benchmarks git repos"
	rm -rf hpo benchmarks
}

###########################################
#   Start HPO
###########################################
function hpo_install() {
	echo
	echo "#######################################"
	echo "Start HPO Server"
	if [ ! -d hpo ]; then
		echo "ERROR: hpo dir not found."
		if [ ${hpo_restart} -eq 1 ]; then
			echo "ERROR: HPO not running. Wrong use of restart command"
		fi
		exit -1
	fi
	pushd hpo >/dev/null
		if [ -z "${HPO_DOCKER_IMAGE}" ]; then
			HPO_VERSION=$(cat version.py | grep "HPO_VERSION" | cut -d "=" -f2 | tr -d '"')
			HPO_DOCKER_IMAGE=${HPO_DOCKER_REPO}:${HPO_VERSION}
		fi
		if [[ ${hpo_restart} -eq 1 ]]; then
			echo
			echo "Terminating the HPO server"
			echo
			./deploy_hpo.sh -c ${CLUSTER_TYPE} -t
			check_err "ERROR: HPO failed to terminate, exiting"
		fi
		if [[ ${CLUSTER_TYPE} == "native" ]]; then
			echo
			echo "Starting hpo with  ./deploy_hpo.sh -c ${CLUSTER_TYPE}"
			echo
			./deploy_hpo.sh -c ${CLUSTER_TYPE} &
			check_err "ERROR: HPO failed to start, exiting"
		else
			echo
			echo "Starting hpo with  ./deploy_hpo.sh -c ${CLUSTER_TYPE} -o ${HPO_DOCKER_IMAGE}"
			echo

			./deploy_hpo.sh -c "${CLUSTER_TYPE}" -o "${HPO_DOCKER_IMAGE}"
			check_err "ERROR: HPO failed to start, exiting"
		fi
	popd >/dev/null
	echo "#######################################"
	echo
}

###########################################
#   Start HPO Experiments
###########################################
## This is function to start experiments with the provided searchspace json.
## It can be customized to run for any usecase, by providing the searchspace json / 
## and modifying Step3 to run the benchmark user needs.
## Currently, it uses TechEmpower benchmark for the demo.
function hpo_experiments() {

	SEARCHSPACE_JSON="hpo_helpers/search_space.json"
	URL="http://localhost:8085"
	exp_json=$(cat ${SEARCHSPACE_JSON})
	if [[ ${exp_json} == "" ]]; then
		err_exit "Error: Searchspace is empty"
        fi
	## Get experiment_id from searchspace
	eid=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.getexperimentid(\"${SEARCHSPACE_JSON}\")")
	## Get total_trials from searchspace
	ttrials=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.gettrials(\"${SEARCHSPACE_JSON}\")")
	if [[ ${eid} == "" || ${ttrials} == "" ]]; then
		err_exit "Error: Invalid search space"
	fi

	echo "#######################################"
	echo "Start a new experiment with search space json"
	## Step 1 : Start a new experiment with provided search space.
	curl -LfSs -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{ "operation": "EXP_TRIAL_GENERATE_NEW",  "search_space": '"${exp_json}"'}'
	check_err "Error: Creating the new experiment failed."

	## Looping through trials of an experiment
	for (( i=0 ; i<${ttrials} ; i++ ))
	do
		## Step 2: Get the HPO config from HPOaaS
		echo "#######################################"
        	echo
		echo "Generate the config for trial ${i}"
		echo
		sleep 10
		HPO_CONFIG=$(curl -LfSs -H 'Accept: application/json' "${URL}"'/experiment_trials?experiment_id='"${eid}"'&trial_number='"${i}")
		check_err "Error: Issue generating the configuration from HPO."
                echo ${HPO_CONFIG}
		echo "${HPO_CONFIG}" > hpo_config.json

		## Step 3: Run the benchmark with HPO config.
		## Output of the benchmark should contain objective function result value and status of the benchmark.
		## Status of the benchmark supported is success and prune
		## Output format expected for BENCHMARK_OUTPUT is "Objfunc_result=0.007914818407446147 Benchmark_status=success"
		## Status of benchmark trial is set to prune, if objective function result value is not a number.
		echo "#######################################"
		echo
	        echo "Run the benchmark for trial ${i}"
		echo
		BENCHMARK_OUTPUT=$(./hpo_helpers/runbenchmark.sh "hpo_config.json" "${SEARCHSPACE_JSON}" "$i")
		echo ${BENCHMARK_OUTPUT}
		obj_result=$(echo ${BENCHMARK_OUTPUT} | cut -d "=" -f2 | cut -d " " -f1)
		trial_state=$(echo ${BENCHMARK_OUTPUT} | cut -d "=" -f3 | cut -d " " -f1)
		### Setting obj_result=0 and trial_state="prune" to contine the experiment if obj_result is nan or trial_state is empty because of any issue with benchmark output.
		number_check='^[0-9,.]+$'
		if ! [[ ${obj_result} =~  ${number_check} ]]; then
			obj_result=0
			trial_state="prune"
		elif [[ ${trial_state} == "" ]]; then
			trial_state="prune"
		fi

		## Step 4: Send the results of benchmark to HPOaaS
		echo "#######################################"
		echo
        	echo "Send the benchmark results for trial ${i}"
		curl  -LfSs -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{"experiment_id" : "'"${eid}"'", "trial_number": '"${i}"', "trial_result": "'"${trial_state}"'", "result_value_type": "double", "result_value": '"${obj_result}"', "operation" : "EXP_TRIAL_RESULT"}'
		check_err "ERROR: Sending the results to HPO failed."
		echo
		sleep 5
		## Step 5 : Generate a subsequent trial
		if (( i < ${ttrial} - 1 )); then
			echo "#######################################"
			echo
	        	echo "Generate subsequent trial of ${i}"
			curl  -LfSs -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{"experiment_id" : "'"${eid}"'", "operation" : "EXP_TRIAL_GENERATE_SUBSEQUENT"}'
			check_err "ERROR: Generating the subsequent trial failed."
			echo
		fi
	done

	echo "#######################################"
	echo
	echo "Experiment complete"
	echo

}

function hpo_start() {
	
	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#        HPO Demo Setup               #"
	echo "#######################################"
	echo

	if [ ${hpo_restart} -eq 0 ]; then
		clone_repos
	fi
	hpo_install
	sleep 5
	## Requires minikube to run the demo benchmark for experiments
	minikube >/dev/null
	check_err "ERROR: minikube not installed. Requires for demo benchmark"
	hpo_experiments
	echo
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! HPO demo setup took ${elapsed_time} seconds"
	echo
	echo "Look into experiment-output.csv for configuration and results of all trials"
	echo

}

function hpo_terminate() {
	echo
	echo "#######################################"
	echo "#       HPO Demo Terminate       #"
	echo "#######################################"
	echo
	pushd hpo >/dev/null
                ./deploy_hpo.sh -t -c ${CLUSTER_TYPE}
		check_err "ERROR: Failed to terminate hpo"
        popd >/dev/null
}

function hpo_cleanup() {

	delete_repos
	## Delete the logs if any before starting the experiment
        rm -rf experiment-output.csv hpo_config.json benchmark.log hpo.log
	echo "Success! HPO demo cleanup completed."
	echo
}

# By default we start the demo and experiment
hpo_restart=0
start_demo=1
# Iterate through the commandline options
while getopts o:c:rst gopts
do
	case "${gopts}" in
		o)
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
	hpo_cleanup
fi
