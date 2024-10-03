#!/bin/bash
#
# Copyright (c) 2024 Red Hat, IBM Corporation and others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# include the common_utils.sh script to access methods
current_dir="$(dirname "$0")"
common_dir="${current_dir}/../../common/"
source ${common_dir}/common_helper.sh

# Default docker image repo
export KRUIZE_DOCKER_REPO="quay.io/kruize/autotune_operator"

# Default cluster
export CLUSTER_TYPE="minikube"

# Target mode, default "crc"; "autotune" is currently broken
export target="crc"

KIND_IP=127.0.0.1
KRUIZE_PORT=8080
KRUIZE_UI_PORT=8081
TECHEMPOWER_PORT=8082

PYTHON_CMD=python3

function usage() {
	echo "Usage: $0 [-s|-t] [-c cluster-type] [l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image]"
	echo "c = supports minikube, kind and openshift cluster-type"
	echo "i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "p = expose prometheus port"
	echo "r = restart kruize only"
	echo "s = start (default), t = terminate"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "n = namespace of benchmark. Default - default"
	echo "d = duration to run the benchmark load"

	exit 1
}

function kruize_bulk() {
  echo "Running bulk_demo.py..."
  "${PYTHON_CMD}" bulk_demo.py -c "${CLUSTER_TYPE}"

}

###########################################
#
###########################################

function kruize_local_bulk() {
	
	bulk_input_json=./bulk_input.json

	echo
	echo "######################################################"
	echo "#     Listing all datsources known to Kruize"
	echo "######################################################"
	echo
	curl http://"${KRUIZE_URL}"/datasources

	echo
	echo "######################################################"
	echo "#     Install default metric profile"
	echo "######################################################"
	echo
	curl -X POST http://${KRUIZE_URL}/createMetricProfile -d @./autotune/manifests/autotune/performance-profiles/resource_optimization_local_monitoring.json
	echo

	echo
	echo "######################################################"
	echo "#     Invoke Kruize bulk service API"
	echo "######################################################"
	echo
	echo "curl -X POST http://${KRUIZE_URL}/bulk -d @./bulk_input.json"
	curl -X POST http://${KRUIZE_URL}/bulk -d @./bulk_input.json
	echo

	echo "Sleeping for 20s before listing the recommendations!"
	sleep 20s 

  	echo
  	echo "######################################################"
  	echo "#     List recommendations "
  	echo "######################################################"
  	echo
	echo "curl http://${KRUIZE_URL}/listRecommendations"
	curl "http://${KRUIZE_URL}/listRecommendations"
  	echo ""

}


###########################################
#  Get URLs
###########################################
function get_urls() {
  	APP_NAMESPACE="${1:-default}"
	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		kubectl_cmd="kubectl -n monitoring"
		kubectl_app_cmd="kubectl -n ${APP_NAMESPACE}"

		MINIKUBE_IP=$(minikube ip)

		KRUIZE_PORT=$(${kubectl_cmd} get svc kruize --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
		KRUIZE_UI_PORT=$(${kubectl_cmd} get svc kruize-ui-nginx-service --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)

		export KRUIZE_URL="${MINIKUBE_IP}:${KRUIZE_PORT}"
		export KRUIZE_UI_URL="${MINIKUBE_IP}:${KRUIZE_UI_PORT}"
	elif [ ${CLUSTER_TYPE} == "kind" ]; then
		export KRUIZE_URL="${KIND_IP}:${KRUIZE_PORT}"
		export KRUIZE_UI_URL="${KIND_IP}:${KRUIZE_UI_PORT}"
	elif [ ${CLUSTER_TYPE} == "openshift" ]; then
		kubectl_cmd="oc -n openshift-tuning"
		kubectl_app_cmd="oc -n ${APP_NAMESPACE}"

		${kubectl_cmd} expose service kruize
		${kubectl_cmd} expose service kruize-ui-nginx-service
		${kubectl_cmd} annotate route kruize --overwrite haproxy.router.openshift.io/timeout=120s

		export KRUIZE_URL=$(${kubectl_cmd} get route kruize --no-headers -o wide -o=custom-columns=NODE:.spec.host)
		export KRUIZE_UI_URL=$(${kubectl_cmd} get route kruize-ui-nginx-service --no-headers -o wide -o=custom-columns=NODE:.spec.host)
	fi
}

# Function to check if a port is in use
function is_port_in_use() {
  local port=$1
  if lsof -i :$port -t >/dev/null 2>&1; then
    return 0 # Port is in use
  else
    return 1 # Port is not in use
  fi
}

###########################################
#  Show URLs
###########################################
function show_urls() {
	echo
	echo
	echo "#######################################"
	echo "#              Kruize               #"
	echo "#######################################"
	echo "Info: Access kruize UI at http://${KRUIZE_UI_URL}"
	echo "Info: List all Kruize Experiments at http://${KRUIZE_URL}/listExperiments"
	echo
}

#
# "local" flag is turned off by default for now. This needs to be set to true.
#
function kruize_local_patch() {
	CRC_DIR="./manifests/crc/default-db-included-installation"
	KRUIZE_CRC_DEPLOY_MANIFEST_OPENSHIFT="${CRC_DIR}/openshift/kruize-crc-openshift.yaml"
	KRUIZE_CRC_DEPLOY_MANIFEST_MINIKUBE="${CRC_DIR}/minikube/kruize-crc-minikube.yaml"

	pushd autotune >/dev/null

		# Checkout mvp_demo to get the latest mvp_demo release version
		git checkout mvp_demo >/dev/null 2>/dev/null

		if [[ ${CLUSTER_TYPE} == "minikube" || ${CLUSTER_TYPE} == "kind" ]]; then
			sed -i 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_MINIKUBE}
		elif [ ${CLUSTER_TYPE} == "openshift" ]; then
			sed -i 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_OPENSHIFT}
		fi
	popd >/dev/null
}


function setup_workload() {
	export ns_name="tfb"
	export count=3

	for ((loop=1; loop<=${count}; loop++)); 
	do                      
		create_namespace ${ns_name}-${loop}
		sleep 5
		benchmarks_install ${ns_name}-${loop} 
	done


	if [ ${CLUSTER_TYPE} == "openshift" ]; then
		for ((loop=1; loop<=${count}; loop++)); 
		do                      
			oc expose svc/tfb-qrh-service -n ${ns_name}-${loop}
			oc get route -n ${ns_name}-${loop}
		done
	fi

	for ((loop=1; loop<=${count}; loop++)); 
	do                      
		apply_benchmark_load ${ns_name}-${loop}
	done
}


function kruize_local_demo_setup() {
	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#       Kruize Local Demo Setup       #"
	echo "#######################################"
	echo

	if [ ${kruize_restart} -eq 0 ]; then
		clone_repos autotune
		cd autotune
		git checkout mvp_demo
		cd ..
		clone_repos benchmarks
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			check_minikube
			minikube >/dev/null
			check_err "ERROR: minikube not installed"
			minikube_start
			prometheus_install autotune
		elif [ ${CLUSTER_TYPE} == "kind" ]; then
			check_kind
			kind >/dev/null
			check_err "ERROR: kind not installed"
			kind_start
			prometheus_install
		fi
		setup_workload
	fi
	kruize_local_patch
	kruize_install
	echo
	# port forward the urls in case of kind
	if [ ${CLUSTER_TYPE} == "kind" ]; then
		port_forward
	fi

	get_urls

	kruize_bulk

	show_urls

	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Kruize demo setup took ${elapsed_time} seconds"
	echo
	if [ ${prometheus} -eq 1 ]; then
		expose_prometheus
	fi
}

###########################################
#  Port forward the URLs
###########################################
function port_forward() {
	kubectl_cmd="kubectl -n monitoring"
	port_flag="false"

	# enable port forwarding to access the endpoints since 'Kind' doesn't expose external IPs
	# Start port forwarding for kruize service in the background
	if is_port_in_use ${KRUIZE_PORT}; then
		echo "Error: Port ${KRUIZE_PORT} is already in use. Port forwarding for kruize service cannot be established."
		port_flag="true"
	else
		${kubectl_cmd} port-forward svc/kruize ${KRUIZE_PORT}:8080 > /dev/null 2>&1 &
	fi
	# Start port forwarding for kruize-ui-nginx-service in the background
	if is_port_in_use ${KRUIZE_UI_PORT}; then
		echo "Error: Port ${KRUIZE_UI_PORT} is already in use. Port forwarding for kruize-ui-nginx-service cannot be established."
		port_flag="true"
	else
		${kubectl_cmd} port-forward svc/kruize-ui-nginx-service ${KRUIZE_UI_PORT}:8080 > /dev/null 2>&1 &
	fi
	# Start port forwarding for tfb-service in the background
	if is_port_in_use ${TECHEMPOWER_PORT}; then
		echo "Error: Port ${TECHEMPOWER_PORT} is already in use. Port forwarding for tfb-service cannot be established."
		port_flag="true"
	else
		kubectl port-forward svc/tfb-qrh-service ${TECHEMPOWER_PORT}:8080 > /dev/null 2>&1 &
	fi

	if ${port_flag} = "true"; then
		echo "Exiting..."
		exit 1
	fi
}


function kruize_local_demo_terminate() {
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#       Kruize Demo Terminate       #"
	echo "#######################################"
	echo
	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube_delete
	elif [ ${CLUSTER_TYPE} == "kind" ]; then
		kind_delete
	else
		kruize_uninstall
	fi
	delete_repos "autotune"
	delete_repos "benchmarks"
	for ((loop=1; loop<=count; loop++));
	do                      
		delete_namespace ${ns_name}-${loop}
	done
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Kruize demo cleanup took ${elapsed_time} seconds"
	echo
}

# Check system configs
sys_cpu_mem_check

# By default we start the demo and dont expose prometheus port
export DOCKER_IMAGES=""
export KRUIZE_DOCKER_IMAGE=""
export benchmark_load=0
export benchmark=0
export prometheus=0
export kruize_restart=0
export start_demo=1
export APP_NAMESPACE="default"
export LOAD_DURATION="1200"
# Iterate through the commandline options
while getopts c:i:n:d:lbprstu: gopts
do
	case "${gopts}" in
		c)
			CLUSTER_TYPE="${OPTARG}"
			;;
		i)
			KRUIZE_DOCKER_IMAGE="${OPTARG}"
			;;
		p)
			prometheus=1
			;;
		r)
			kruize_restart=1
			;;
		s)
			start_demo=1
			;;
		t)
			start_demo=0
			;;
		u)
			KRUIZE_UI_DOCKER_IMAGE="${OPTARG}"
			;;
		n)
			APP_NAMESPACE="${OPTARG}"
			;;
		d)
			LOAD_DURATION="${OPTARG}"
			;;
		*)
			usage
	esac
done

if [ ${start_demo} -eq 1 ]; then
	kruize_local_demo_setup
else
	kruize_local_demo_terminate
fi
