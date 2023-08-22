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

target="crc"
visualize=0

PYTHON_CMD=python3

function usage() {
	echo "Usage: $0 [-s|-t] [-o kruize-image] [-r] [-c cluster-type] [-d] [--days=] [--visualize]"
	echo "s = start (default), t = terminate"
	echo "r = restart kruize monitoring only"
	echo "o = kruize image. Default - docker.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "c = supports minikube and openshift cluster-type"
	echo "d = duration of benchmark warmup/measurement cycles"
	echo "p = expose prometheus port"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "days = number of days data to push into kruize. Do not exceed 15."
	echo "visualize = Visualize the resource usage and recommendations in grafana (Yet to be implemented)"
	exit 1
}

## Checks for the pre-requisites to run the monitoring demo
function prereq_check() {
	# Python is required only to run the monitoring experiment
	"${PYTHON_CMD}" --version >/dev/null 2>/dev/null
	check_err "ERROR: "${PYTHON_CMD}" not installed. Required to start the demo. Check if all dependencies ("${PYTHON_CMD}", minikube) are installed."

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube >/dev/null 2>/dev/null
		check_err "ERROR: minikube not installed."
		kubectl get pods >/dev/null 2>/dev/null
		check_err "ERROR: minikube not running. "
		## Check if prometheus is running for valid benchmark results.
		prometheus_pod_running=$(kubectl get pods --all-namespaces | grep "prometheus-k8s-0")
		if [ "${prometheus_pod_running}" == "" ]; then
			err_exit "Install prometheus for valid results from benchmark."
		fi
	fi
}

###########################################
#   Kruize Install
###########################################
function kruize_install() {
	echo
	echo "#######################################"
	echo "6. Installing Kruize"
	if [ ! -d autotune ]; then
		echo "ERROR: autotune dir not found."
		if [[ ${autotune_restart} -eq 1 ]]; then
			echo "ERROR: Kruize not running. Wrong use of restart command"
		fi
		exit -1
	fi
	pushd autotune >/dev/null
		# Checkout mvp_demo to get the latest mvp_demo release version
		git checkout mvp_demo >/dev/null 2>/dev/null

		AUTOTUNE_VERSION="$(grep -A 1 "autotune" pom.xml | grep version | awk -F '>' '{ split($2, a, "<"); print a[1] }')"
    # Kruize UI repo
		KRUIZE_UI_REPO="quay.io/kruize/kruize-ui"
		# Checkout the tag related to the last published mvp_demo version
		git checkout "${AUTOTUNE_VERSION}" >/dev/null 2>/dev/null

		echo "Terminating existing installation of kruize with  ./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t"
		./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t >/dev/null 2>/dev/null
		sleep 5
		if [ -z "${AUTOTUNE_DOCKER_IMAGE}" ]; then
			AUTOTUNE_DOCKER_IMAGE=${AUTOTUNE_DOCKER_REPO}:${AUTOTUNE_VERSION}
		fi
		DOCKER_IMAGES="-i ${AUTOTUNE_DOCKER_IMAGE}"
		if [ ! -z "${HPO_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -o ${AUTOTUNE_DOCKER_IMAGE}"
		fi
		echo
		echo "Starting2 kruize installation with  ./deploy.sh -c ${CLUSTER_TYPE} ${DOCKER_IMAGES} -m ${target}"
		echo

		if [ ${EXPERIMENT_START} -eq 0 ]; then
			CURR_DRIVER=$(minikube config get driver 2>/dev/null)
			if [ "${CURR_DRIVER}" == "docker" ]; then
				echo "Setting docker env"
				eval $(minikube docker-env)
			elif [ "${CURR_DRIVER}" == "podman" ]; then
				echo "Setting podman env"
				eval $(minikube podman-env)
			fi
		fi

		./deploy.sh -c ${CLUSTER_TYPE} ${DOCKER_IMAGES} -m ${target}
		check_err "ERROR: kruize failed to start, exiting"

		echo -n "Waiting 40 seconds for Autotune to sync with Prometheus..."
		sleep 40
		echo "done"
	popd >/dev/null
	echo "#######################################"
	echo
}

function remote_monitoring_experiments() {
	echo "Running demo.py with ${DATA_DAYS} day data..."
  "${PYTHON_CMD}" demo.py -c "${CLUSTER_TYPE}" -d "${DATA_DAYS}"
}

function pronosana_backfill() {
	usage_data_json=$1
	recommendations_data_json=$1

	echo ""
	echo "Invoking pronosana backfill using the below command..."
	echo ""
	pushd pronosana > /dev/null
		echo "./pronosana backfill ${CLUSTER_TYPE} --usage-data-json=${PWD}/usage_data.json --recommendation-data-json=${PWD}/recommendations_data.json"
		./pronosana backfill ${CLUSTER_TYPE} --usage-data-json=${PWD}/usage_data.json --recommendation-data-json=${PWD}/recommendations_data.json
	popd > /dev/null
}


function check_pronosana_setup() {
	echo ""
	echo "Checking if all the pronosana containers are running"
	check_pod="pronosana-deployment"
	echo "Info: Waiting for ${check_pod} to come up....."
	err_wait=0
	counter=0
	kubectl_cmd="kubectl -n pronosana"
	while true;
	do
		sleep 2
		${kubectl_cmd} get pods | grep ${check_pod}
		pod_stat=$(${kubectl_cmd} get pods | grep ${check_pod} | awk '{ print $3 }')
		case "${pod_stat}" in
			"Running")
				echo "Info: ${check_pod} deploy succeeded: ${pod_stat}"
				err=0
				break;
				;;
			"Error")
				# On Error, wait for 10 seconds before exiting.
				err_wait=$(( err_wait + 1 ))
				if [ ${err_wait} -gt 5 ]; then
					echo "Error: ${check_pod} deploy failed: ${pod_stat}"
					err=-1
					break;
				fi
				;;
			*)
				sleep 2
				if [ $counter == 200 ]; then
					${kubectl_cmd} describe pod ${scheck_pod}
					echo "ERROR: Prometheus Pods failed to come up!"
					exit -1
				fi
				((counter++))
				;;
		esac
	done

}

###########################################
#   Pronosana Init
###########################################
function pronosana_init() {
	echo
	echo "#######################################"
	pushd pronosana >/dev/null
		"${PYTHON_CMD}" -m pip install --user -r requirements.txt >/dev/null 2>&1
		echo "6. Initializing pronosana"
		./pronosana cleanup ${CLUSTER_TYPE}
		sleep 30
		./pronosana init ${CLUSTER_TYPE}
		sleep 30
		check_pronosana_setup
	popd >/dev/null
	echo "#######################################"
	echo
}

function remote_monitoring_demo_start() {

	minikube >/dev/null
	check_err "ERROR: minikube not installed"
	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#           Demo Setup                #"
	echo "#######################################"
	echo
	echo "--> Clone Required Repos"

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		echo "--> Setup minikube"
		echo "--> Installs Prometheus"
	fi

	if [ ${visualize} -eq 1 ]; then
		echo "--> Installs Pronosana"
	fi
	echo "--> Installs Kruize"
	echo "--> Creates experiments in remote monitoring mode"
	echo "--> Updates resource usage metrics for one of the experiments"
	echo "--> Fetches the recommendations from Kruize"
	if [ ${visualize} -eq 1 ]; then
		echo "--> Posts the recommendations from kruize to thanos"
		echo "--> Launches grafana in the web browser"
	fi
	echo

	if [ ${monitoring_restart} -eq 0 ]; then
		clone_repos autotune

		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			minikube_start
			echo "Calling prometheus_install"
			prometheus_install
			echo "Calling prometheus_install done"
		fi

		if [ ${visualize} -eq 1 ]; then
			clone_repos pronosana
			rm -rf pronosana
			git clone https://github.com/bharathappali/pronosana.git
			echo "visualize = $visualize"
			pronosana_init
		fi
	fi

	# Check for pre-requisites to run the demo
	"${PYTHON_CMD}" -m pip install --user -r requirements.txt >/dev/null 2>&1
	prereq_check ${CLUSTER_TYPE}

	kruize_install

	# Create an experiment, update results and fetch recommendations using Kruize REST APIs
	remote_monitoring_experiments

	echo
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Monitoring demo setup took ${elapsed_time} seconds"
	echo
	if [ ${prometheus} -eq 1 ]; then
		expose_prometheus
	fi

	if [ ${visualize} -eq 1 ]; then
		pronosana_backfill "${PWD}/combined_data.json"

		sleep 20
		echo ""
		echo "Grafana is launched in the web browser, login into it and search for pronosana dashboard to view the recommendations"
		echo "If there are any issues with launching the browser, you can manually open this link - http://localhost:3000/login"
		echo ""
	fi

}

function remote_monitoring_demo_terminate() {
	echo
	echo "#######################################"
	echo "#     Monitoring Demo Terminate       #"
	echo "#######################################"
	echo
	pushd autotune >/dev/null
		./deploy.sh -t -c ${CLUSTER_TYPE}
		echo "ERROR: Failed to terminate kruize monitoring"
		echo
	popd >/dev/null
}

function pronosana_terminate() {
	echo
	echo "#######################################"
	echo "#          Pronosana Terminate        #"
	echo "#######################################"
	echo
	pushd pronosana >/dev/null
		./pronosana cleanup ${CLUSTER_TYPE}
	popd >/dev/null
}

function remote_monitoring_demo_cleanup() {
	echo
	echo "#######################################"
	echo "#    Monitoring Demo setup cleanup    #"
	echo "#######################################"
	echo

	delete_repos autotune

	if [ ${visualize} -eq 1 ]; then
		delete_repos pronosana
	fi

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube_delete
	fi

	echo "Success! Monitoring Demo setup cleanup completed."
	echo
}

# By default we start the demo & experiment and we dont expose prometheus port
prometheus=0
monitoring_restart=0
start_demo=1
EXPERIMENT_START=0
terminate=0
# Default no.of data entries to an experiment
DATA_DAYS=1
# Iterate through the commandline options
while getopts o:c:d:prstu:-: gopts; do
	case ${gopts} in
         -)
                case "${OPTARG}" in
                        visualize)
                                visualize=1
                                ;;
			days=*)
				DATA_DAYS=${OPTARG#*=}
				;;
			*)
				;;
		esac
		;;

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
	u)
		KRUIZE_UI_DOCKER_IMAGE="${OPTARG}"
		;;
	*)
		usage
		;;
	esac
done
if [ ${start_demo} -eq 1 ]; then
	remote_monitoring_demo_start
else
	remote_monitoring_demo_terminate
	if [ ${visualize} -eq 1 ]; then
		pronosana_terminate
	fi
	remote_monitoring_demo_cleanup
fi
