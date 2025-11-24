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
common_dir="${current_dir}/../../common/"
source ${common_dir}/common_helper.sh

# Default docker image repos
AUTOTUNE_DOCKER_REPO="docker.io/kruize/autotune_operator"

export LOG_FILE="${current_dir}/kruize-demo.log"

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
	echo >> "${LOG_FILE}" 2>&1
	echo "#######################################" >> "${LOG_FILE}" 2>&1
	echo "6. Installing Kruize" >> "${LOG_FILE}" 2>&1
	if [ ! -d autotune ]; then
		echo "❌ ERROR: autotune dir not found."
		if [[ ${autotune_restart} -eq 1 ]]; then
			echo "❌ ERROR: Kruize not running. Wrong use of restart command"
		fi
		echo "For detailed logs, look in ${LOG_FILE}"
		exit -1
	fi
	pushd autotune >/dev/null
		# Checkout mvp_demo to get the latest mvp_demo release version
		git checkout mvp_demo >/dev/null 2>/dev/null
		kruize_local_disable >> "${LOG_FILE}" 2>&1

		AUTOTUNE_VERSION="$(grep -A 1 "autotune" pom.xml | grep version | awk -F '>' '{ split($2, a, "<"); print a[1] }')"
		# Kruize UI repo
		KRUIZE_UI_REPO="quay.io/kruize/kruize-ui"
		# Checkout the tag related to the last published mvp_demo version
		git checkout "${AUTOTUNE_VERSION}" >/dev/null 2>/dev/null >> "${LOG_FILE}" 2>&1
		echo "Terminating existing installation of kruize with  ./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t" >> "${LOG_FILE}" 2>&1
		./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t >/dev/null 2>/dev/null
		sleep 5
		if [ -z "${AUTOTUNE_DOCKER_IMAGE}" ]; then
			AUTOTUNE_DOCKER_IMAGE=${AUTOTUNE_DOCKER_REPO}:${AUTOTUNE_VERSION}
		fi
		DOCKER_IMAGES="-i ${AUTOTUNE_DOCKER_IMAGE}"
		if [ ! -z "${HPO_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -o ${AUTOTUNE_DOCKER_IMAGE}"
		fi
		if [ ! -z "${KRUIZE_UI_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -u ${KRUIZE_UI_DOCKER_IMAGE}"
		fi
		echo >> "${LOG_FILE}" 2>&1
		echo "Starting kruize installation with  ./deploy.sh -c ${CLUSTER_TYPE} ${DOCKER_IMAGES} -m ${target}" >> "${LOG_FILE}" 2>&1
		echo >> "${LOG_FILE}" 2>&1

		if [ ${EXPERIMENT_START} -eq 0 ]; then
			CURR_DRIVER=$(minikube config get driver 2>/dev/null)
			if [ "${CURR_DRIVER}" == "docker" ]; then
				echo "Setting docker env" >> "${LOG_FILE}" 2>&1
				eval $(minikube docker-env) >> "${LOG_FILE}" 2>&1
			elif [ "${CURR_DRIVER}" == "podman" ]; then
				echo "Setting podman env" >> "${LOG_FILE}" 2>&1
				eval $(minikube podman-env) >> "${LOG_FILE}" 2>&1
			fi
		fi

		./deploy.sh -c ${CLUSTER_TYPE} ${DOCKER_IMAGES} -m ${target} >> "${LOG_FILE}" 2>&1
		check_err "ERROR: kruize failed to start, exiting"

		echo -n "Waiting 40 seconds for Autotune to sync with Prometheus..." >> "${LOG_FILE}" 2>&1
		sleep 40
		echo "done" >> "${LOG_FILE}" 2>&1
	popd >/dev/null
	echo "#######################################" >> "${LOG_FILE}" 2>&1
	echo >> "${LOG_FILE}" 2>&1
}

function remote_monitoring_experiments() {
	echo "Running demo.py with ${DATA_DAYS} day data..." >> "${LOG_FILE}" 2>&1
  "${PYTHON_CMD}" demo.py -c "${CLUSTER_TYPE}" -d "${DATA_DAYS}"
}

function pronosana_backfill() {
	usage_data_json=$1
	recommendations_data_json=$1

	echo "" >> "${LOG_FILE}" 2>&1
	echo "Invoking pronosana backfill using the below command..." >> "${LOG_FILE}" 2>&1
	echo "" >> "${LOG_FILE}" 2>&1
	pushd pronosana > /dev/null
		echo "./pronosana backfill ${CLUSTER_TYPE} --usage-data-json=${PWD}/usage_data.json --recommendation-data-json=${PWD}/recommendations_data.json" >> "${LOG_FILE}" 2>&1
		./pronosana backfill ${CLUSTER_TYPE} --usage-data-json=${PWD}/usage_data.json --recommendation-data-json=${PWD}/recommendations_data.json >> "${LOG_FILE}" 2>&1
	popd > /dev/null
}


function check_pronosana_setup() {
	echo "" >> "${LOG_FILE}" 2>&1
	echo "Checking if all the pronosana containers are running" >> "${LOG_FILE}" 2>&1
	check_pod="pronosana-deployment"
	echo "Info: Waiting for ${check_pod} to come up....." >> "${LOG_FILE}" 2>&1
	err_wait=0
	counter=0
	kubectl_cmd="kubectl -n pronosana"
	while true;
	do
		sleep 2
		${kubectl_cmd} get pods | grep ${check_pod} >> "${LOG_FILE}" 2>&1
		pod_stat=$(${kubectl_cmd} get pods | grep ${check_pod} | awk '{ print $3 }')
		case "${pod_stat}" in
			"Running")
				echo "Info: ${check_pod} deploy succeeded: ${pod_stat}" >> "${LOG_FILE}" 2>&1
				err=0
				break;
				;;
			"Error")
				# On Error, wait for 10 seconds before exiting.
				err_wait=$(( err_wait + 1 ))
				if [ ${err_wait} -gt 5 ]; then
					echo "Error: ${check_pod} deploy failed: ${pod_stat}" >> "${LOG_FILE}" 2>&1
					err=-1
					break;
				fi
				;;
			*)
				sleep 2
				if [ $counter == 200 ]; then
					${kubectl_cmd} describe pod ${scheck_pod}
					echo "❌ ERROR: Prometheus Pods failed to come up!"
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
	echo >> "${LOG_FILE}" 2>&1
	echo "#######################################" >> "${LOG_FILE}" 2>&1
	pushd pronosana >/dev/null
		"${PYTHON_CMD}" -m pip install --user -r requirements.txt >/dev/null >> "${LOG_FILE}" 2>&1
		echo "6. Initializing pronosana" >> "${LOG_FILE}" 2>&1
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

	# Start all the installs
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "# Kruize Demo Setup on ${CLUSTER_TYPE} " | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube >/dev/null
      		check_err "ERROR: minikube not installed"
		echo "--> Setup minikube" >> "${LOG_FILE}" 2>&1
		echo "--> Installs Prometheus" >> "${LOG_FILE}" 2>&1
	fi

	if [ ${visualize} -eq 1 ]; then
		echo "--> Installs Pronosana" >> "${LOG_FILE}" 2>&1
	fi
	echo "--> Installs Kruize" >> "${LOG_FILE}" 2>&1
	echo "--> Creates experiments in remote monitoring mode" >> "${LOG_FILE}" 2>&1
	echo "--> Updates resource usage metrics for one of the experiments" >> "${LOG_FILE}" 2>&1
	echo "--> Fetches the recommendations from Kruize" >> "${LOG_FILE}" 2>&1
	if [ ${visualize} -eq 1 ]; then
		echo "--> Posts the recommendations from kruize to thanos" >> "${LOG_FILE}" 2>&1
		echo "--> Launches grafana in the web browser" >> "${LOG_FILE}" 2>&1
	fi
	echo

	if [ ${monitoring_restart} -eq 0 ]; then
		echo -n "🔄 Pulling required repositories... "
		clone_repos autotune
		echo "Done!"

		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			echo -n "🔄 Installing minikube and prometheus! Please wait..."
			minikube_start
			echo "Calling prometheus_install" >> "${LOG_FILE}" 2>&1
			prometheus_install
			echo "Calling prometheus_install done" >> "${LOG_FILE}" 2>&1
			echo "✅ Installation of minikube and prometheus complete!"
		fi

		if [ ${visualize} -eq 1 ]; then
			echo -n "🔄 Installing pronsona! Please wait..."
			clone_repos pronosana
			rm -rf pronosana
			git clone https://github.com/bharathappali/pronosana.git
			echo "visualize = $visualize" >> "${LOG_FILE}" 2>&1
			pronosana_init
			echo "✅ Installation of pronosona complete!"
		fi
	fi

	# Check for pre-requisites to run the demo
	"${PYTHON_CMD}" -m pip install --user -r requirements.txt >/dev/null 2>&1
	echo -n "🔄 Checking pre requisites! Please wait..."
	prereq_check ${CLUSTER_TYPE}
	echo "✅ Complete!"

	echo -n "🔄 Installing kruize! Please wait..."
	kruize_install
	echo "✅ Installation of kruize complete!"

	# Create an experiment, update results and fetch recommendations using Kruize REST APIs
	echo -n "🔄 Creating remote monitoring experiments and updating results! Please wait..."
	remote_monitoring_experiments >> "${LOG_FILE}" 2>&1
	echo "✅ Complete!"

	echo
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "🕒 Success! Remote Monitoring demo setup took ${elapsed_time} seconds"
	echo
	if [ ${prometheus} -eq 1 ]; then
		expose_prometheus
	fi

	if [ ${visualize} -eq 1 ]; then
		pronosana_backfill "${PWD}/combined_data.json" >> "${LOG_FILE}" 2>&1

		sleep 20
		echo "" >> "${LOG_FILE}" 2>&1
		echo "Grafana is launched in the web browser, login into it and search for pronosana dashboard to view the recommendations" >> "${LOG_FILE}" 2>&1
		echo "If there are any issues with launching the browser, you can manually open this link - http://localhost:3000/login" >> "${LOG_FILE}" 2>&1
		echo "" >> "${LOG_FILE}" 2>&1
	fi

}

function remote_monitoring_demo_terminate() {
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "#     Monitoring Demo Terminate       #" | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"
	pushd autotune >/dev/null
		./deploy.sh -t -c ${CLUSTER_TYPE}  >> "${LOG_FILE}" 2>&1
		echo "ERROR: Failed to terminate kruize monitoring"  >> "${LOG_FILE}" 2>&1
		echo  >> "${LOG_FILE}" 2>&1
	popd >/dev/null
}

function pronosana_terminate() {
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "#          Pronosana Terminate        #" | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"
	pushd pronosana >/dev/null
		./pronosana cleanup ${CLUSTER_TYPE}  >> "${LOG_FILE}" 2>&1
	popd >/dev/null
}

function remote_monitoring_demo_cleanup() {
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "#    Monitoring Demo setup cleanup    #" | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"

	delete_repos autotune >> "${LOG_FILE}" 2>&1

	if [ ${visualize} -eq 1 ]; then
		delete_repos pronosana >> "${LOG_FILE}" 2>&1
	fi

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube_delete >> "${LOG_FILE}" 2>&1
	fi

	echo "🕒 Success! Remote Monitoring demo cleanup completed!"
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
                          if [ "${OPTERR}" == 1 ] && [ "${OPTSPEC:0:1}" != ":" ]; then
                          				echo "Unknown option --${OPTARG}" >&2
                          				usage
                     			fi
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
	echo > "${LOG_FILE}" 2>&1
	remote_monitoring_demo_start
	echo "For detailed logs, look in kruize-demo.log"
        echo
else
	echo >> "${LOG_FILE}" 2>&1
	remote_monitoring_demo_terminate
	if [ ${visualize} -eq 1 ]; then
		pronosana_terminate
	fi
	remote_monitoring_demo_cleanup
	echo "For detailed logs, look in kruize-demo.log"
        echo
fi

