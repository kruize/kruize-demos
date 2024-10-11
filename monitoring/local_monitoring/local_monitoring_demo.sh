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

export demo="local"
if [ ${start_demo} -eq 1 ]; then
	kruize_local_demo_setup
elif [ ${start_demo} -eq 2 ]; then
	kruize_local_demo_update
else
	kruize_local_demo_terminate
fi
