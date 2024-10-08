#!/bin/bash
#
# Copyright (c) 2020, 2022 Red Hat, IBM Corporation and others.
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
export CLUSTER_TYPE="kind"

# Target mode, default "crc"; "autotune" is currently broken
export target="crc"

KIND_IP=127.0.0.1
KRUIZE_PORT=8080
KRUIZE_UI_PORT=8081
TECHEMPOWER_PORT=8082

function usage() {
	echo "Usage: $0 [-s|-t] [-c cluster-type] [-l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image] [-b] [-n namespace] [-d load-duration] [-m benchmark-manifests]"
	echo "c = supports minikube, kind, aks and openshift cluster-type"
	echo "i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "l = Run a load against the benchmark"
	echo "p = expose prometheus port"
	echo "r = restart kruize only"
	echo "s = start (default), t = terminate"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "b = deploy the benchmark."
	echo "n = namespace of benchmark. Default - default"
	echo "d = duration to run the benchmark load"
	echo "m = manifests of the benchmark"

	exit 1
}


###########################################
#
###########################################

function kruize_local() {
	#
	export DATASOURCE="prometheus-1"
	export CLUSTER_NAME="default"
	# Metric Profile JSON
	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		resource_optimization_local_monitoring="${current_dir}/autotune/manifests/autotune/performance-profiles/resource_optimization_local_monitoring_norecordingrules.json"
	else
		resource_optimization_local_monitoring="${current_dir}/autotune/manifests/autotune/performance-profiles/resource_optimization_local_monitoring.json"
	fi

	echo
	echo "######################################################"
	echo "#     Listing all datsources known to Kruize"
	echo "######################################################"
	echo
	curl http://"${KRUIZE_URL}"/datasources

	echo
	echo "######################################################"
	echo "#     Import metadata from prometheus-1 datasource"
	echo "######################################################"
	echo
	curl --location http://"${KRUIZE_URL}"/dsmetadata \
	--header 'Content-Type: application/json' \
	--data '{
	   "version": "v1.0",
	   "datasource_name": "prometheus-1"
	}'

	echo
	echo "######################################################"
	echo "#     Display metadata from prometheus-1 datasource"
	echo "######################################################"
	echo
	curl "http://${KRUIZE_URL}/dsmetadata?datasource=${DATASOURCE}&verbose=true"
	echo

	echo
	echo "######################################################"
	echo "#     Display metadata for ${APP_NAMESPACE} namespace"
	echo "######################################################"
	echo
	curl "http://${KRUIZE_URL}/dsmetadata?datasource=${DATASOURCE}&cluster_name=${CLUSTER_NAME}&namespace=${APP_NAMESPACE}&verbose=true"
	echo

	echo
	echo "######################################################"
	echo "#     Delete previously created experiment"
	echo "######################################################"
	echo
	echo "curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./create_tfb_exp.json"
	curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./create_tfb_exp.json
	echo "curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./create_tfb-db_exp.json"
	curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./create_tfb-db_exp.json
	echo "curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json"
	curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json
	echo

	echo
	echo "######################################################"
	echo "#     Install default metric profile"
	echo "######################################################"
	echo
	curl -X POST http://${KRUIZE_URL}/createMetricProfile -d @$resource_optimization_local_monitoring
	echo

	echo
        echo "######################################################"
        echo "#     Update kruize experiment jsons"
        echo "######################################################"
        echo
	sed -i 's/"namespace": "default"/"namespace": "'"${APP_NAMESPACE}"'"/' ./create_tfb_exp.json
	sed -i 's/"namespace": "default"/"namespace": "'"${APP_NAMESPACE}"'"/' ./create_tfb-db_exp.json
	sed -i 's/"namespace_name": "default"/"namespace_name": "'"${APP_NAMESPACE}"'"/' ./create_namespace_exp.json
	echo

	echo
	echo "######################################################"
	echo "#     Create kruize experiment"
	echo "######################################################"
	echo
	echo "curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_tfb_exp.json"
	curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_tfb_exp.json
	echo "curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_tfb-db_exp.json"
	curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_tfb-db_exp.json
	echo "curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json"
	curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json
	echo

	apply_benchmark_load ${APP_NAMESPACE}

  	echo
  	echo "######################################################"
  	echo "#     Generate recommendations for every experiment"
  	echo "######################################################"
  	echo
	echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_tfb_benchmark"
	curl -X POST "http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_tfb_benchmark"
	echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_tfb-db_benchmark"
	curl -X POST "http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_tfb-db_benchmark"
	echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_app_namespace"
	curl -X POST "http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_app_namespace"

	echo ""
	echo "######################################################"
	echo "ATLEAST TWO DATAPOINTS ARE REQUIRED TO GENERATE RECOMMENDATIONS!"
	echo "PLEASE WAIT FOR FEW MINS AND GENERATE THE RECOMMENDATIONS AGAIN IF NO RECOMMENDATIONS ARE AVAILABLE!"
	echo "######################################################"
	echo

  	echo
  	echo "Generate fresh recommendations using"
	echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_tfb_benchmark"
	echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_tfb-db_benchmark"
	echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_app_namespace"
  	echo
  	echo "List Recommendations using "
	echo "curl http://${KRUIZE_URL}/listRecommendations?experiment_name=monitor_tfb_benchmark"
	echo "curl http://${KRUIZE_URL}/listRecommendations?experiment_name=monitor_tfb-db_benchmark"
	echo "curl http://${KRUIZE_URL}/listRecommendations?experiment_name=monitor_app_namespace"
  	echo
  	echo "######################################################"
  	echo
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

		TECHEMPOWER_PORT=$(${kubectl_app_cmd} get svc tfb-qrh-service --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
		TECHEMPOWER_IP=$(${kubectl_app_cmd} get pods -l=app=tfb-qrh-deployment -o wide -o=custom-columns=NODE:.spec.nodeName --no-headers)

		export KRUIZE_URL="${MINIKUBE_IP}:${KRUIZE_PORT}"
		export KRUIZE_UI_URL="${MINIKUBE_IP}:${KRUIZE_UI_PORT}"
		export TECHEMPOWER_URL="${MINIKUBE_IP}:${TECHEMPOWER_PORT}"

	elif [ "${CLUSTER_TYPE}" == "aks" ]; then
		kubectl_cmd="kubectl -n monitoring"

		# Expose kruize/kruize-ui-nginx-service via LoadBalancer
		KRUIZE_SERVICE_URL=$(${kubectl_cmd} get svc kruize -o custom-columns=EXTERNAL-IP:.status.loadBalancer.ingress[*].ip --no-headers)
		KRUIZE_UI_SERVICE_URL=$(${kubectl_cmd} get svc kruize-ui-nginx-service -o custom-columns=EXTERNAL-IP:.status.loadBalancer.ingress[*].ip --no-headers)

		export KRUIZE_URL="${KRUIZE_SERVICE_URL}:8080"
		export KRUIZE_UI_URL="${KRUIZE_UI_SERVICE_URL}:8080"
		unset TECHEMPOWER_IP
		export TECHEMPOWER_IP=$(kubectl -n default get svc tfb-qrh-service -o custom-columns=EXTERNAL-IP:.status.loadBalancer.ingress[*].ip --no-headers)
		export TECHEMPOWER_URL="${TECHEMPOWER_IP}:8080"
	
	elif [ ${CLUSTER_TYPE} == "kind" ]; then
		export KRUIZE_URL="${KIND_IP}:${KRUIZE_PORT}"
		export KRUIZE_UI_URL="${KIND_IP}:${KRUIZE_UI_PORT}"
		export TECHEMPOWER_URL="${KIND_IP}:${TECHEMPOWER_PORT}"
	elif [ ${CLUSTER_TYPE} == "openshift" ]; then
		kubectl_cmd="oc -n openshift-tuning"
		kubectl_app_cmd="oc -n ${APP_NAMESPACE}"

		${kubectl_cmd} expose service kruize
		${kubectl_cmd} expose service kruize-ui-nginx-service
		${kubectl_cmd} annotate route kruize --overwrite haproxy.router.openshift.io/timeout=60s

		${kubectl_app_cmd} expose service tfb-qrh-service

		export KRUIZE_URL=$(${kubectl_cmd} get route kruize --no-headers -o wide -o=custom-columns=NODE:.spec.host)
		export KRUIZE_UI_URL=$(${kubectl_cmd} get route kruize-ui-nginx-service --no-headers -o wide -o=custom-columns=NODE:.spec.host)
		export TECHEMPOWER_URL=$(${kubectl_app_cmd} get route tfb-qrh-service --no-headers -o wide -o=custom-columns=NODE:.spec.host)
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
	echo "#######################################"
	echo "#             Quarkus App             #"
	echo "#######################################"
	echo "Info: Access techempower app at http://${TECHEMPOWER_URL}/db"
	echo "Info: Access techempower app metrics at http://${TECHEMPOWER_URL}/q/metrics"
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
	KRUIZE_CRC_DEPLOY_MANIFEST_AKS="${CRC_DIR}/aks/kruize-crc-aks.yaml"

	pushd autotune >/dev/null
		# Checkout mvp_demo to get the latest mvp_demo release version
		git checkout mvp_demo >/dev/null 2>/dev/null

		if [ ${CLUSTER_TYPE} == "kind" ] || [ ${CLUSTER_TYPE} == "minikube" ]; then
			sed -i 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_MINIKUBE}
		elif [ ${CLUSTER_TYPE} == "openshift" ]; then
			sed -i 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_OPENSHIFT}
		elif [ ${CLUSTER_TYPE} == "aks" ]; then
                        perl -pi -e 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_AKS}
		fi
	popd >/dev/null
}


#
#
#
function kruize_local_demo_setup() {
	# Start all the installs
	start_time=$(get_date)
	namespace_quota_yaml="${current_dir}/namespace_resource_quota.yaml"
	echo
	echo "#######################################"
	echo "#       Kruize Local Demo Setup       #"
	echo "#######################################"
	echo

	if [ ${kruize_restart} -eq 0 ]; then
		clone_repos autotune
		clone_repos benchmarks
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			sys_cpu_mem_check
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
		create_namespace ${APP_NAMESPACE}
		apply_namespace_resource_quota ${APP_NAMESPACE} ${namespace_quota_yaml}
		benchmarks_install ${APP_NAMESPACE} ${BENCHMARK_MANIFESTS}
	fi
	kruize_local_patch
	kruize_install
	echo
	# port forward the urls in case of kind
	if [ ${CLUSTER_TYPE} == "kind" ]; then
		port_forward
	fi

	get_urls ${APP_NAMESPACE}

	# Run the Kruize Local experiments
	kruize_local

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

function kruize_local_demo_update() {
        # Start all the installs
        start_time=$(get_date)
	if [ ${benchmark} -eq 1 ]; then
		echo
                echo "############################################"
                echo "#     Deploy TFB on ${APP_NAMESPACE}        "
                echo "############################################"
                echo
		create_namespace ${APP_NAMESPACE}
		benchmarks_install ${APP_NAMESPACE} "resource_provisioning_manifests"
                echo "Success! Running the benchmark in ${APP_NAMESPACE}"
                echo
	fi
	if [ ${benchmark_load} -eq 1 ]; then
		echo
		echo "#######################################"
		echo "#     Apply the benchmark load        #"
		echo "#######################################"
		echo
		apply_benchmark_load ${APP_NAMESPACE} ${LOAD_DURATION}
		echo "Success! Running the benchmark load for ${LOAD_DURATION} seconds"
		echo
	fi

        end_time=$(get_date)
        elapsed_time=$(time_diff "${start_time}" "${end_time}")
        echo "Success! Benchmark updates took ${elapsed_time} seconds"
        echo
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
	benchmarks_uninstall ${APP_NAMESPACE} ${BENCHMARK_MANIFESTS}
	delete_namespace_resource_quota ${APP_NAMESPACE}
	delete_repos autotune
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Kruize demo cleanup took ${elapsed_time} seconds"
	echo
}

# Check system configs
sys_cpu_mem_check ${CLUSTER_TYPE}

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
export BENCHMARK_MANIFESTS="resource_provisioning_manifests"

# Iterate through the commandline options
while getopts c:i:n:d:m:lbprstu: gopts
do
	case "${gopts}" in
		c)
			CLUSTER_TYPE="${OPTARG}"
			;;
		i)
			KRUIZE_DOCKER_IMAGE="${OPTARG}"
			;;
		l)
			start_demo=2
			benchmark_load=1
			;;
		b)
			start_demo=2
			benchmark=1
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
			export APP_NAMESPACE="${OPTARG}"
			;;
		d)
			LOAD_DURATION="${OPTARG}"
			;;
		m)
			BENCHMARK_MANIFESTS="${OPTARG}"
			;;
		*)
			usage
	esac
done

if [ ${start_demo} -eq 1 ]; then
	kruize_local_demo_setup
elif [ ${start_demo} -eq 2 ]; then
	kruize_local_demo_update
else
	kruize_local_demo_terminate
fi
