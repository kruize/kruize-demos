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
#
##### Script for capturing HPO (Hyper Parameter Optimization) resource usage by scaling experiments - 1x, 10x, 100x #####

# Get the absolute path of current directory
CURRENT_DIR="$(dirname "$(realpath "$0")")"
SCRIPTS_DIR="./scripts"

failed=0
start_demo=1
hpo_restart=0
cluster_type="minikube"
HPO_REPO="hpo"
AUTOTUNE_REPO="autotune"
HPO_CONTAINER_IMAGE="kruize/hpo:test"

function usage() {
	echo "Usage: $0 [ -s|-t ] [ -o hpo-image ] [ -c cluster-type ] [ -d resultsdir ] [ -b Benchmark Server ]"
	echo "s = start (default), t = terminate"
	echo "c = supports cluster-type minikube, openshift to start HPO service"
	echo "b = Benchmark server, mandatory when cluster type is openshift"
	echo " Environment Variables to be set: REGISTRY, REGISTRY_EMAIL, REGISTRY_USERNAME, REGISTRY_PASSWORD"
	echo " [Example - REGISTRY: docker.io, quay.io, etc]"
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

# Check if the prometheus is already deployed, if not invoke the script to deploy prometheus on minikube
function setup_prometheus() {
	kubectl_cmd="kubectl"
	prometheus_pod_running=$(${kubectl_cmd} get pods --all-namespaces | grep "prometheus-k8s-1")
	
	pushd ${AUTOTUNE_REPO} > /dev/null
		if [ "${prometheus_pod_running}" == "" ]; then
			echo "Running prometheus script..."
			./scripts/prometheus_on_minikube.sh -as
		fi
	popd > /dev/null
}

###########################################
#   Clone git Repos
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

	if [ ! -d autotune ]; then
		git clone git@github.com:kruize/autotune.git 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kruize/autotune.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kruize/autotune failed."
	fi
	echo "done"
	echo "#######################################"
	echo
}

###########################################
#   Cleanup HPO git Repos
###########################################

function delete_repos() {
	echo "Delete hpo and autotune git repo"
	rm -rf hpo autotune
}

## Checks for the pre-requisites to run the demo benchmark with HPO.
function prereq_check() {
        ## Requires minikube to run the demo benchmark for experiments

	if [ "${cluster_type}" == "minikube" ]; then
	        minikube >/dev/null 2>/dev/null
        	check_err "ERROR: minikube not installed. Check if all other dependencies (git,curl,bc,jq) are installed."
	        kubectl get pods >/dev/null 2>/dev/null
        	check_err "ERROR: minikube not installed. Check if all other dependencies (git,curl,bc,jq) are installed."
	fi

        ## Requires curl
        curl --version >/dev/null 2>/dev/null
        check_err "ERROR: curl not installed. Check if all other dependencies (bc,jq) are installed."

        ## Requires bc
        bc --version >/dev/null 2>/dev/null
        check_err "ERROR: bc not installed. Required for running benchmark. Check if all other dependencies (bc,jq) are installed."
        ## Requires jq
        jq --version >/dev/null 2>/dev/null
        check_err "ERROR: jq not installed. "

	# Check if the cluster_type is minikube., if so deploy prometheus
	if [ "${cluster_type}" == "minikube" ]; then
		if [ ${hpo_restart} -eq 0 ]; then
			echo
			echo "#######################################"
			echo "Installing Prometheus on minikube"
			setup_prometheus
			echo "done"
			echo "#######################################"
			echo
		fi
		kubectl -n monitoring port-forward svc/prometheus-k8s 9090:9090 > /dev/null &
	fi
}


###########################################
#   HPO scale tests 
###########################################
function hpo_scale_tests() {

	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#           HPO Scale tests           #"
	echo "#######################################"
	echo
	echo "--> Starts HPO"
	echo "--> Runs experiments (1x, 10x, 100x) with 5 trials and captures resource usage"
	echo "--> Performs 3 iterations and computes the avg, min, max"
	echo "--> Edit the variables num_experiments, N_TRIALS or ITERATIONS to change this"
	echo

	if [ ${hpo_restart} -eq 0 ]; then
		clone_repos
	fi
	prereq_check

	# Stop the HPO servers
	echo "Terminating any running HPO servers..."
	hpo_terminate ${cluster_type}
	echo "Terminating any running HPO servers...Done"

	# Defaults for experiments, trials and iterations. 
	num_experiments=(1 10 100)
	N_TRIALS=5
	ITERATIONS=3
	LOG="${RESULTS_DIR}/hpo_scale_tests.log"

	echo ""
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" | tee -a ${LOG}
	echo "                    Running HPO Scale Tests " | tee -a ${LOG}
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"| tee -a ${LOG}

	echo "failed = $failed"
	for NUM_EXPS in ${num_experiments[@]}
	do
		SCALE_TEST_RES_DIR="${RESULTS_DIR}/${NUM_EXPS}x-result"
		echo "SCALE_TEST_RES_DIR = ${SCALE_TEST_RES_DIR}"
		mkdir -p "${SCALE_TEST_RES_DIR}"
		run_experiments "${NUM_EXPS}" "${N_TRIALS}" "${SCALE_TEST_RES_DIR}" "${ITERATIONS}"

		${SCRIPTS_DIR}/parsemetrics-promql.sh ${ITERATIONS} ${SCALE_TEST_RES_DIR} ${hpo_instances} ${WARMUP_CYCLES} ${MEASURE_CYCLES} ${SCRIPTS_DIR} ${NUM_EXPS}

	done

	echo "Results of experiments"
	echo "EXPERIMENTS COUNT , INSTANCES ,  CPU_USAGE , MEM_USAGE(MB) , FS_USAGE(B) , NW_RECEIVE_BANDWIDTH_USAGE , NW_TRANSMIT_BANDWIDTH_USAGE , CPU_MIN , CPU_MAX , MEM_MIN , MEM_MAX , FS_MIN , FS_MAX , NW_RECEIVE_BANDWIDTH_MIN , NW_RECEIVE_BANDWIDTH_MAX , NW_TRANSMIT_BANDWIDTH_MIN , NW_TRANSMIT_BANDWIDTH_MAX" > "${RESULTS_DIR}/res_usage_output.csv"
	for NUM_EXPS in ${num_experiments[@]}
	do
		cat "${RESULTS_DIR}/${NUM_EXPS}x-result/Metrics-prom.log"
		paste "${RESULTS_DIR}/${NUM_EXPS}x-result/Metrics-prom.log" >> "${RESULTS_DIR}/res_usage_output.csv"
	done

	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")

	# print the testsuite summary
	echo ""
	echo "HPO Scale tests took ${elapsed_time} seconds to complete"
	echo "failed = $failed"
	if [ "${failed}" == "0" ]; then
		echo "Check ${RESULTS_DIR}/res_usage_output.csv for resource usage details!"
	else
		echo "Test failed - Check result logs for errors!"
	        echo "RESULTS DIR - ${RESULTS_DIR}"	
	fi
	echo ""
}

function run_experiments() {
	NUM_EXPS=$1
	N_TRIALS=$2
	RESULTS_=$3
	ITERATIONS=$4

	TRIAL_DURATION=10
	BUFFER=5

	DURATION=`expr $NUM_EXPS \* $TRIAL_DURATION \* $N_TRIALS + $BUFFER`
	#DURATION=300

	WARMUP_CYCLES=0
	MEASURE_CYCLES=1

	# No. of instances of HPO
	hpo_instances=1

	for (( iter=0; iter<${ITERATIONS}; iter++ ))
	do
		
		echo "*************************************************" | tee -a ${LOG}
		echo "Starting Iteration $iter" | tee -a ${LOG}
		echo "*************************************************" | tee -a ${LOG}
		echo ""

		# Deploy HPO 
		RESULTS_I="${RESULTS_}/ITR-${iter}"
		mkdir -p "${RESULTS_I}"
		SERV_LOG="${RESULTS_I}/service.log"

		echo "RESULTSDIR - ${RESULTS_I}" | tee -a ${LOG}
		echo "" | tee -a ${LOG}

		if [ ${cluster_type} == "native" ]; then
			deploy_hpo ${cluster_type} ${SERV_LOG}
		else
			deploy_hpo ${cluster_type} ${HPO_CONTAINER_IMAGE} ${SERV_LOG}
		fi

		# Check if HPO services are started
		check_server_status "${SERV_LOG}"

		# Measurement runs
		TYPE="measure"
		run_iteration ${NUM_EXPS} ${N_TRIALS} ${DURATION} ${MEASURE_CYCLES} ${TYPE} ${RESULTS_I}

		# Store the docker logs
		if [ ${cluster_type} == "docker" ]; then
			docker logs hpo_docker_container > ${SERV_LOG} 2>&1
		elif [[ ${cluster_type} == "minikube" || ${cluster_type} == "openshift" ]]; then
			hpo_pod=$(kubectl get pod -n ${namespace} | grep hpo | cut -d " " -f1)
	                kubectl -n ${namespace} logs ${hpo_pod} > "${SERV_LOG}" 2>&1
        	fi

		# Terminate any running HPO servers
		echo "Terminating any running HPO servers..." | tee -a ${LOG}
		hpo_terminate ${cluster_type}
		echo "Terminating any running HPO servers...Done" | tee -a ${LOG}
		sleep 2

		echo "*************************************************" | tee -a ${LOG}
		echo "Completed Iteration $iter"
		echo "*************************************************" | tee -a ${LOG}
		echo ""
	done
}

function run_iteration() {
	NUM_EXPS=$1
	N_TRIALS=$2
	DURATION=$3
	CYCLES=$4
	TYPE=$5
	RES_DIR=$6

	# Start the metrics collection script
	if [ "${cluster_type}" == "openshift" ]; then
		BENCHMARK_SERVER="${server}"
	else 
		BENCHMARK_SERVER="localhost"
	fi

	echo "BENCHMARK_SERVER = ${BENCHMARK_SERVER} pod = $hpo_pod"
	APP_NAME="${hpo_pod}"
	# Run experiments
	for (( run=0; run<${CYCLES}; run++ ))
	do
		echo "*************************************************" | tee -a ${LOG}
		echo "Starting $TYPE-$run " | tee -a ${LOG}
		echo "*************************************************" | tee -a ${LOG}
		echo ""

		echo "Invoking get metrics cmd - ${SCRIPTS_DIR}/getmetrics-promql.sh ${TYPE}-${run} ${DURATION} ${RES_DIR} ${BENCHMARK_SERVER} ${APP_NAME} ${cluster_type} &"
		${SCRIPTS_DIR}/getmetrics-promql.sh ${TYPE}-${run} ${DURATION} ${RES_DIR} ${BENCHMARK_SERVER} ${APP_NAME} ${cluster_type} &

		hpo_run_experiments "${NUM_EXPS}" "${N_TRIALS}" "${RES_DIR}"

		echo "*************************************************" | tee -a ${LOG}
		echo "Completed $TYPE-$run " | tee -a ${LOG}
		echo "*************************************************" | tee -a ${LOG}
		echo ""
	done


}

# Post the experiment result to HPO /experiment_trials API
# input: Experiment result
# output: Create the Curl command with given JSON and get the result
function post_experiment_result_json() {
	exp_result=$1

	echo ""
	form_hpo_api_url "experiment_trials"

	post_result=$(curl -s -H 'Content-Type: application/json' ${hpo_url}  -d "${exp_result}"  -w '\n%{http_code}' 2>&1)

	# Example curl command used to post the experiment result: curl -H "Content-Type: application/json" -d {"experiment_id" : null, "trial_number": 0, "trial_result": "success", "result_value_type": "double", "result_value": 98.78, "operation" : "EXP_TRIAL_RESULT"} http://localhost:8085/experiment_trials -w n%{http_code}
	post_exp_result_cmd="curl -s -H 'Content-Type: application/json' ${hpo_url} -d "${exp_result}" -w '\n%{http_code}'"

	echo "" | tee -a ${LOG_} ${LOG}
	echo "Command used to post the experiment result= ${post_exp_result_cmd}" | tee -a ${LOG_} ${LOG}
	echo "" | tee -a ${LOG_} ${LOG}

	echo "${post_result}" >> ${LOG_} ${LOG}

	http_code=$(tail -n1 <<< "${post_result}")
	response=$(echo -e "${post_result}" | tail -2 | head -1)
	echo "Response is ${response}" >> ${LOG_} ${LOG}
	echo "http_code = $http_code response = $response"
}

function verify_result() {
	test_info=$1
	http_code=$2
	expected_http_code=$3

	if [[ "${http_code}" -eq "000" ]]; then
		failed=1
	else
		if [[ ${http_code} -ne ${expected_http_code} ]]; then
			failed=1
			echo "${test_info} failed - http_code is not as expected, http_code = ${http_code} expected code = ${expected_http_code}" | tee -a ${LOG}
		fi
	fi
}


# Post a JSON object to HPO(Hyper Parameter Optimization) module
# input: JSON object
# output: Create the Curl command with given JSON and get the result
function post_experiment_json() {
	json_array_=$1
	echo ""
	form_hpo_api_url "experiment_trials"

	post_cmd=$(curl -s -H 'Content-Type: application/json' ${hpo_url}  -d "${json_array_}"  -w '\n%{http_code}' 2>&1)

	# Example curl command: curl -v -s -H 'Content-Type: application/json' http://localhost:8085/experiment_trials -d '{"operation":"EXP_TRIAL_GENERATE_NEW","search_space":{"experiment_name":"petclinic-sample-2-75884c5549-npvgd","experiment_id":"a123","value_type":"double","hpo_algo_impl":"optuna_tpe","objective_function":"transaction_response_time","tunables":[{"value_type":"double","lower_bound":150,"name":"memoryRequest","upper_bound":300,"step":1},{"value_type":"double","lower_bound":1,"name":"cpuRequest","upper_bound":3,"step":0.01}],"slo_class":"response_time","direction":"minimize"}}' 

	post_experiment_cmd="curl -s -H 'Content-Type: application/json' ${hpo_url} -d '${json_array_}'  -w '\n%{http_code}'"

	echo "" | tee -a ${LOG_} ${LOG}
	echo "Curl command used to post the experiment = ${post_experiment_cmd}" | tee -a ${LOG_} ${LOG}
	echo "" | tee -a ${LOG_} ${LOG}

	echo "${post_cmd}" >> ${LOG_} ${LOG}


	http_code=$(tail -n1 <<< "${post_cmd}")
	response=$(echo -e "${post_cmd}" | tail -2 | head -1)

	echo "Response is ${response}" >> ${LOG_} ${LOG}
	echo "http_code is $http_code Response is ${response}"
}

function form_hpo_api_url {
	API=$1
	# Form the URL command based on the cluster type

	case $cluster_type in
		native|docker) 
			PORT="8085"
			SERVER_IP="localhost"
			;;
		minikube)
			SERVER_IP=$(minikube ip)
			PORT=$(kubectl -n ${namespace} get svc hpo --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
			;;
		 openshift)
                        SERVER_IP=$(oc -n ${namespace} get pods -l=app=hpo -o wide -o=custom-columns=NODE:.spec.nodeName --no-headers)
                        PORT=$(oc -n ${namespace} get svc hpo --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
                        ;;
		*);;
	esac

	hpo_url="http://${SERVER_IP}:${PORT}/${API}"
        echo "HPO_URL = $hpo_url"
}

# Deploy hpo
# input: cluster type, hpo container image
# output: Deploy hpo based on the parameter passed
function deploy_hpo() {
	cluster_type=$1
	HPO_CONTAINER_IMAGE=$2

	pushd ${HPO_REPO} > /dev/null
	
	if [ ${cluster_type} == "native" ]; then
		echo
		echo
		log=$2
		cmd="./deploy_hpo.sh -c ${cluster_type} > ${log} 2>&1 &"
		echo "Command to deploy hpo - ${cmd}"
		./deploy_hpo.sh -c ${cluster_type} > ${log} 2>&1 &
	elif [ ${cluster_type} == "minikube" ]; then
                cmd="./deploy_hpo.sh -c ${cluster_type} -o ${HPO_CONTAINER_IMAGE} -n ${namespace}"
                echo "Command to deploy hpo - ${cmd}"
                ./deploy_hpo.sh -c ${cluster_type} -o ${HPO_CONTAINER_IMAGE} -n ${namespace}
        elif [ ${cluster_type} == "openshift" ]; then
                cmd="./deploy_hpo.sh -c ${cluster_type} -o ${HPO_CONTAINER_IMAGE} -n ${namespace}"
                echo "Command to deploy hpo - ${cmd}"
                ./deploy_hpo.sh -c ${cluster_type} -o ${HPO_CONTAINER_IMAGE} -n ${namespace}
	else 
		cmd="./deploy_hpo.sh -c ${cluster_type} -o ${HPO_CONTAINER_IMAGE}"
		echo "Command to deploy hpo - ${cmd}"
		./deploy_hpo.sh -c ${cluster_type} -o ${HPO_CONTAINER_IMAGE}
	fi
	
	status="$?"
	# Check if hpo is deployed.
	if [[ "${status}" -eq "1" ]]; then
		echo "Error deploying hpo" >>/dev/stderr
		exit -1
	fi

	if [ ${cluster_type} == "docker" ]; then
  		sleep 2
		echo "Capturing HPO service log into $3"
		log=$3
		docker logs hpo_docker_container > "${log}" 2>&1
	elif [[ ${cluster_type} == "minikube" || ${cluster_type} == "openshift" ]]; then
		sleep 2
		echo "Capturing HPO service log into $3"
		echo "Namespace = $namespace"
		log=$3
		hpo_pod=$(kubectl get pod -n ${namespace} | grep hpo | cut -d " " -f1)
		kubectl -n ${namespace} logs -f ${hpo_pod} > "${log}" & 2>&1
	fi

	popd > /dev/null
	echo "Deploying HPO as a service...Done"
}

# Remove the hpo setup
function hpo_terminate() {
	cluster_type=$1

	pushd ${HPO_REPO} > /dev/null
		echo  "Terminating hpo..."
		cmd="./deploy_hpo.sh -c ${cluster_type} -t -n ${namespace}"
		echo "CMD = ${cmd}"
		./deploy_hpo.sh -c ${cluster_type} -t -n ${namespace}
	popd > /dev/null
	echo "done"
}

# Check if the servers have started
function check_server_status() {
	log=$1

	echo "Wait for HPO service to come up"
        form_hpo_api_url "experiment_trials"
	echo "Server - $SERVER_IP PORT - $PORT"

	#if service does not start within 5 minutes (300s) fail the test
	timeout 30 bash -c 'while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://${SERVER_IP}:${PORT})" != "200" ]]; do sleep 1; done' || false

	if [ -z "${log}" ]; then
		echo "Service log - $log not found!"
		exit 1
	fi

	service_log_msg="Access REST Service at"

	if grep -q "${service_log_msg}" "${log}" ; then
		echo "HPO REST API service started successfully..." | tee -a ${LOG_} ${LOG}
	else
		echo "Error Starting the HPO REST API service..." | tee -a ${LOG_} ${LOG}
		echo "See ${log} for more details" | tee -a ${LOG_} ${LOG}
		cat "${log}"
		exit 1
	fi

	grpc_service_log_msg="Starting gRPC server at"
	if grep -q "${grpc_service_log_msg}" "${log}" ; then
		echo "HPO GRPC API service started successfully..." | tee -a ${LOG_} ${LOG}
	else
		echo "Error Starting the HPO GRPC API service..." | tee -a ${LOG_} ${LOG}
		echo "See ${log} for more details" | tee -a ${LOG_} ${LOG}
		cat "${log}"
		exit 1
	fi
}

# Run Multiple experiments test for HPO REST service
function hpo_run_experiments() {
	echo "In hpo_run_experiments failed = $failed"

	# Set the no. of experiments
	NUM_EXPS=$1

	# Set the no. of trials
	N_TRIALS=$2

	exp_dir=$3
	EXP_RES_DIR="${exp_dir}/exp_logs"
	mkdir -p "${EXP_RES_DIR}"

	failed=0

	echo "RESULTSDIR - ${EXP_RES_DIR}" | tee -a ${LOG}
	echo "" | tee -a ${LOG}

	expected_http_code="200"

	exp_json='{"operation":"EXP_TRIAL_GENERATE_NEW","search_space":{"experiment_name":"petclinic-sample-2-75884c5549-npvgd","total_trials":5,"parallel_trials":1,"experiment_id":"a123","value_type":"double","hpo_algo_impl":"optuna_tpe","objective_function":"transaction_response_time","tunables":[{"value_type":"double","lower_bound":150,"name":"memoryRequest","upper_bound":300,"step":1},{"value_type":"double","lower_bound":1,"name":"cpuRequest","upper_bound":3,"step":0.01}],"direction":"minimize"}}'

	## Start multiple experiments
	for (( i=1 ; i<=${NUM_EXPS} ; i++ ))
	do
		LOG_="${EXP_RES_DIR}/hpo-exp-${i}.log"
		# Post the experiment
		echo "Start a new experiment with the search space json..." | tee -a ${LOG}

		# Replace the experiment name
		json=$(echo $exp_json | sed -e 's/petclinic-sample-2-75884c5549-npvgd/petclinic-sample-'${i}'/')
		post_experiment_json "$json"
		verify_result "Post new experiment" "${http_code}" "${expected_http_code}"
	done

	## Loop through the trials
	for (( trial_num=0 ; trial_num<${N_TRIALS} ; trial_num++ ))
	do

		for (( i=1 ; i<=${NUM_EXPS} ; i++ ))
		do
			exp_name="petclinic-sample-${i}"
			echo ""
			echo "*********************************** Experiment ${exp_name} and trial_number ${trial_num} *************************************"
			LOG_="${EXP_RES_DIR}/hpo-exp${i}-trial${trial_num}.log"

			# Get the config from HPO
			sleep 2
			echo ""
			echo "Generate the config for experiment ${i} and trial ${trial_num}..." | tee -a ${LOG}
			echo ""

			curl="curl -H 'Accept: application/json'"

			get_trial_json=$(${curl} ''${hpo_url}'?experiment_name='${exp_name}'&trial_number='${trial_num}'' -w '\n%{http_code}' 2>&1)

			get_trial_json_cmd="${curl} ${hpo_url}?experiment_name="${exp_name}"&trial_number=${trial_num} -w '\n%{http_code}'"
			echo "command used to query the experiment_trial API = ${get_trial_json_cmd}" | tee -a ${LOG}

			http_code=$(tail -n1 <<< "${get_trial_json}")
			response=$(echo -e "${get_trial_json}" | tail -2 | head -1)
			response=$(echo ${response} | cut -c 4-)

			echo "${response}" 
			verify_result "Get config from hpo for experiment ${exp_name} and trial ${trial_num}" "${http_code}" "${expected_http_code}"

			# Added a sleep to mimic experiment run
			sleep 3 

			# Post the experiment result to hpo
			echo "" | tee -a ${LOG}
			echo "Post the experiment result for experiment ${exp_name} and trial ${trial_num}..." | tee -a ${LOG}
			trial_result="success"
			result_value="98.7"
			exp_result_json='{"experiment_name":"'${exp_name}'","trial_number":'${trial_num}',"trial_result":"'${trial_result}'","result_value_type":"double","result_value":'${result_value}',"operation":"EXP_TRIAL_RESULT"}'
			post_experiment_result_json ${exp_result_json}
			verify_result "Post experiment result for experiment ${exp_name} and trial ${trial_num}" "${http_code}" "${expected_http_code}"
	
			sleep 2

			# Generate a subsequent trial
			if [[ ${trial_num} < $((N_TRIALS-1)) ]]; then
				echo "" | tee -a ${LOG}
				echo "Generate subsequent config for experiment ${exp_name} after trial ${trial_num} ..." | tee -a ${LOG}
				subsequent_trial='{"experiment_name":"'${exp_name}'","operation":"EXP_TRIAL_GENERATE_SUBSEQUENT"}'
				post_experiment_json ${subsequent_trial}
				verify_result "Post subsequent for experiment ${exp_name} after trial ${trial_num}" "${http_code}" "${expected_http_code}"
			fi
		done
	done

	for (( i=1 ; i<=${NUM_EXPS} ; i++ ))
	do
		exp_name="\"petclinic-sample-${i}"\"
		stop_experiment='{"experiment_name":'${exp_name}',"operation":"EXP_STOP"}'
		post_experiment_json ${stop_experiment}
		verify_result "Stop running experiment ${exp_name}" "${http_code}" "200"
	done

	echo "In hpo_run_experiments failed = $failed"

}

# Check if the cluster_type is one of kubernetes clusters
# input: cluster type
# output: If cluster type is not supported then print the usage
function check_cluster_type() {
        if [ -z "${cluster_type}" ]; then
                echo
                usage
        fi
        case "${cluster_type}" in
                minikube|openshift)
                ;;
                *)
                echo "Error: Cluster type **${cluster_type}** is not supported  "
                usage
        esac
}


# Iterate through the commandline options
while getopts o:n:b:c:d:rst gopts
do
	case "${gopts}" in
		o)
			HPO_CONTAINER_IMAGE="${OPTARG}"		
			;;
		n)
			namespace="${OPTARG}"
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
			cluster_type="${OPTARG}"
			check_cluster_type
			;;
		d)
			resultsdir="${OPTARG}"
			;;
		b)
			server="${OPTARG}"
			;;
		*)
			usage
	esac
done

# Set the root for result directory 
if [ -z "${resultsdir}" ]; then
	RESULTS_DIR="${PWD}/hpo_scale_test_results_$(date +%Y%m%d:%T)"
else
	RESULTS_DIR="${resultsdir}/hpo_scale_test_results_$(date +%Y%m%d:%T)"
fi

if [ "${cluster_type}" == "openshift" ]; then
	if [ -z "${server}" ]; then
		echo "Specify the BENCHMARK server using -b option!"
		usage
	fi
fi

# In case of Minikube and Openshift, check if registry credentials are set as Environment Variables
if [[ "${cluster_type}" == "minikube" || "${cluster_type}" == "openshift" ]]; then
        if [ -z "${REGISTRY}" ] || [ -z "${REGISTRY_USERNAME}" ] || [ -z "${REGISTRY_PASSWORD}" ] || [ -z "${REGISTRY_EMAIL}" ]; then
                echo "You need to set the environment variables first for Kubernetes secret creation"
                usage
                exit -1
        fi
fi

if [ -z "${namespace}" ]; then
        case $cluster_type in
                minikube)
                        namespace="monitoring"
                        ;;
                openshift)
                        namespace="openshift-tuning"
                        ;;
                *);;
        esac
fi


mkdir -p "${RESULTS_DIR}"

SETUP_LOG="${RESULTS_DIR}/setup.log"

if [ ${start_demo} -eq 1 ]; then
	# Invoke hpo scale tests
	pkill -f "port-forward"
	hpo_scale_tests > >(tee "${RESULTS_DIR}/hpo_scale_tests.log") 2>&1
	hpo_terminate "${cluster_type}"
	pkill -f "port-forward"
else
	hpo_terminate "${cluster_type}"
	pkill -f "port-forward"
	delete_repos	
fi
