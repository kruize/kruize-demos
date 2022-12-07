#!/bin/bash
#
# Copyright (c) 2022, 2022 Red Hat, IBM Corporation and others.
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

current_dir="$(dirname "$0")"
source ${current_dir}/../common_helper.sh

# Default docker image repos
AUTOTUNE_DOCKER_REPO="docker.io/kruize/autotune_operator"

# Default cluster
CLUSTER_TYPE="minikube"

# Default duration of benchmark warmup/measurement cycles in seconds.
DURATION=60
PY_CMD="python3"
LOGFILE="${PWD}/monitoring.log"

function usage() {
	echo "Usage: $0 [-s|-t] [-o autotune-image] [-r] [-c cluster-type] [-d]"
	echo "s = start (default), t = terminate"
	echo "r = restart kruize monitoring only"
	echo "c = supports minikube and openshift cluster-type"
	echo "d = duration of benchmark warmup/measurement cycles"
	echo "p = expose prometheus port"
	exit 1
}

## Checks for the pre-requisites to run the monitoring demo
function prereq_check() {
	# Python is required only to run the monitoring experiment 
	python3 --version >/dev/null 2>/dev/null
	check_err "ERROR: python3 not installed. Required to start HPO. Check if all dependencies (python3,minikube,php,java11,wget,curl,zip,bc,jq) are installed."

	## Requires minikube to run the demo benchmark for experiments
	minikube >/dev/null 2>/dev/null
	check_err "ERROR: minikube not installed. Required for running benchmark. Check if all other dependencies (php,java11,git,wget,curl,zip,bc,jq) are installed."
	kubectl get pods >/dev/null 2>/dev/null
	check_err "ERROR: minikube not running. Required for running benchmark"
	## Check if prometheus is running for valid benchmark results.
	prometheus_pod_running=$(kubectl get pods --all-namespaces | grep "prometheus-k8s-0")
	if [ "${prometheus_pod_running}" == "" ]; then
		err_exit "Install prometheus for valid results from benchmark."
	fi
	## Requires java 11
	java -version >/dev/null 2>/dev/null
	check_err "Error: java is not found. Requires Java 11 for running benchmark."
	JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
	if [[ ${JAVA_VERSION} < "11" ]]; then
		err_exit "ERROR: Java 11 is required."
	fi
	## Requires wget
	wget --version >/dev/null 2>/dev/null
	check_err "ERROR: wget not installed. Required for running benchmark. Check if all other dependencies (php,curl,zip,bc,jq) are installed."
	## Requires curl
	curl --version >/dev/null 2>/dev/null
	check_err "ERROR: curl not installed. Required for running benchmark. Check if all other dependencies (php,zip,bc,jq) are installed."
	## Requires bc
	bc --version >/dev/null 2>/dev/null
	check_err "ERROR: bc not installed. Required for running benchmark. Check if all other dependencies (php,zip,jq) are installed."
	## Requires jq
	jq --version >/dev/null 2>/dev/null
	check_err "ERROR: jq not installed. Required for running benchmark. Check if all other dependencies (php,zip) are installed."
	## Requires zip
	zip --version >/dev/null 2>/dev/null
	check_err "ERROR: zip not installed. Required for running benchmark. Check if other dependencies (php) are installed."
	## Requires php
	php --version >/dev/null 2>/dev/null
	check_err "ERROR: php not installed. Required for running benchmark."
}

###########################################
#   Autotune Install
###########################################
function autotune_install() {
	echo
	echo "#######################################"
	echo "6. Installing Autotune"
	if [ ! -d autotune ]; then
		echo "ERROR: autotune dir not found."
		if [ ${autotune_restart} -eq 1 ]; then
			echo "ERROR: autotune not running. Wrong use of restart command"
		fi
		exit -1
	fi
	pushd autotune >/dev/null
		# Checkout the mvp_demo branch for now
		git checkout mvp_demo

		AUTOTUNE_VERSION="$(grep -A 1 "autotune" pom.xml | grep version | awk -F '>' '{ split($2, a, "<"); print a[1] }')"
		YAML_TEMPLATE="./manifests/autotune-operator-deployment.yaml_template"
		YAML_TEMPLATE_OLD="./manifests/autotune-operator-deployment.yaml_template.old"

		./deploy.sh -c minikube -t 2>/dev/null
		sleep 5
		if [ -z "${AUTOTUNE_DOCKER_IMAGE}" ]; then
			AUTOTUNE_DOCKER_IMAGE=${AUTOTUNE_DOCKER_REPO}:${AUTOTUNE_VERSION}
		fi
		DOCKER_IMAGES="-i ${AUTOTUNE_DOCKER_IMAGE}"
		if [ ! -z "${HPO_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -o ${AUTOTUNE_DOCKER_IMAGE}"
		fi
		echo
		echo "Starting install with  ./deploy.sh -c minikube ${DOCKER_IMAGES}"
		echo

		if [ ${EXPERIMENT_START} -eq 0 ]; then
			cp ${YAML_TEMPLATE} ${YAML_TEMPLATE_OLD}
			sed -e "s/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g" ${YAML_TEMPLATE_OLD} > ${YAML_TEMPLATE}
			CURR_DRIVER=$(minikube config get driver 2>/dev/null)
			if [ "${CURR_DRIVER}" == "docker" ]; then
				echo "Setting docker env"
				eval $(minikube docker-env)
			elif [ "${CURR_DRIVER}" == "podman" ]; then
				echo "Setting podman env"
				eval $(minikube podman-env)
			fi
		fi

		./deploy.sh -c minikube ${DOCKER_IMAGES}
		check_err "ERROR: Autotune failed to start, exiting"

		if [ ${EXPERIMENT_START} -eq 0 ]; then
			cp ${YAML_TEMPLATE_OLD} ${YAML_TEMPLATE} 2>/dev/null
		fi
		echo -n "Waiting 30 seconds for Autotune to sync with Prometheus..."
		sleep 30
		echo "done"
	popd >/dev/null
	echo "#######################################"
	echo
}

function monitoring_experiments() {
	echo "Running demo.py..."
	python demo.py -c "${CLUSTER_TYPE}"
}

function monitoring_demo_start() {

	minikube >/dev/null
	check_err "ERROR: minikube not installed"
	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#           Demo Setup                #"
	echo "#######################################"
	echo
	echo "--> Clone Repos"
	echo "--> Setup minikube"
	echo "--> Installs Prometheus"
	echo "--> Installs TFB benchmark"
	echo "--> Creates kruize monitoring experiments & updates TFB results"
	echo "--> Posts the recommendations from kruize to thanos"
	echo

	if [ ${monitoring_restart} -eq 0 ]; then
		clone_repos autotune
		minikube_start
		prometheus_install
		benchmarks_install
	fi

	# Check for pre-requisites to run the demo benchmark with HPO.
	prereq_check ${CLUSTER_TYPE}

	autotune_install
	
	monitoring_experiments

	echo
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Monitoring demo setup took ${elapsed_time} seconds"
	echo
	echo "Look into experiment-output.csv for configuration and results of all trials"
	echo "and benchmark.log for demo benchmark logs"
	echo
	if [ ${prometheus} -eq 1 ]; then
		expose_prometheus
	fi

}

function monitoring_demo_terminate() {
	echo
	echo "#######################################"
	echo "#     Monitoring Demo Terminate       #"
	echo "#######################################"
	echo
	pushd hpo >/dev/null
		./deploy_hpo.sh -t -c ${CLUSTER_TYPE}
		echo "ERROR: Failed to terminate hpo"
		echo
	popd >/dev/null
}

function monitoring_demo_cleanup() {
	echo
	echo "#######################################"
	echo "#    Monitoring Demo setup cleanup    #"
	echo "#######################################"
	echo
	pushd autotune >/dev/null
		./deploy_autotune.sh -t -c ${CLUSTER_TYPE}
		echo "ERROR: Failed to terminate autotune"
		echo
	popd >/dev/null

	delete_repos autotune
	minikube_delete
	
	echo "Success! Monitoring Demo setup cleanup completed."
	echo
}

# By default we start the demo & experiment and we dont expose prometheus port
prometheus=0
monitoring_restart=0
start_demo=1
EXPERIMENT_START=0
# Iterate through the commandline options
while getopts o:c:d:prst gopts
do
	case "${gopts}" in
		o)
			AUTOTUNE_DOCKER_IMAGE="${OPTARG}"
			;;
		p)
			prometheus=1
			;;
		r)
			monitoring_restart=1
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
		d)
			DURATION="${OPTARG}"
			;;
		*)
			usage
	esac
done

if [ ${start_demo} -eq 1 ]; then
	monitoring_demo_start
else
	monitoring_demo_terminate
	monitoring_demo_cleanup
fi
