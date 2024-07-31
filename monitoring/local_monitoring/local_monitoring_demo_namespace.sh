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

function usage() {
	echo "Usage: $0 [-s|-t] [-c cluster-type] [-l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image] [-b] [-n namespace] [-d load-duration] "
	echo "c = supports minikube and openshift cluster-type"
	echo "i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "l = Run a load against the benchmark"
	echo "p = expose prometheus port"
	echo "r = restart kruize only"
	echo "s = start (default), t = terminate"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "b = deploy the benchmark."
	echo "n = namespace of benchmark. Default - default"
	echo "d = duration to run the benchmark load"

	exit 1
}


###########################################
#
###########################################

function kruize_local() {
	#
	export DATASOURCE="prometheus-1"
	export CLUSTER_NAME="default"
	export NAMESPACE="default"

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
	echo "#     Install default performance profile"
	echo "######################################################"
	echo
	curl -X POST http://${KRUIZE_URL}/createMetricProfile -d @./resource_optimization_openshift.json
	echo

  	echo
  	echo "##############################################################"
  	echo "#     Multiple Import Metadata from prometheus-1 datasource"
  	echo "##############################################################"
  	echo
  	create_namespace
	kubectl apply -f namespace_quota.yaml
  	benchmarks_install "test-multiple-import" "resource_provisioning_manifests"	
  	sleep 35
  	get_urls "test-multiple-import"
  	apply_benchmark_load "test-multiple-import"
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
  	echo "############################################################"
  	echo "#     Display metadata for test-multiple-import namespace"
  	echo "############################################################"
  	echo
  	curl "http://${KRUIZE_URL}/dsmetadata?datasource=${DATASOURCE}&cluster_name=${CLUSTER_NAME}&namespace=test-multiple-import&verbose=true"
  	echo

  	echo
  	echo "######################################################"
  	echo "#     Delete previously created experiment"
  	echo "######################################################"
  	echo
  	echo "curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json"
  	curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json
  	echo

  	echo
  	echo "######################################################"
  	echo "#     Create kruize experiment"
  	echo "######################################################"
  	echo
  	echo "curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json"
  	curl -X POST http://${KRUIZE_URL}/createExperiment -d @./create_namespace_exp.json
	echo

	echo "Sleeping for 3mins before generating the recommendations!"
	sleep 3m

  	echo
  	echo "######################################################"
  	echo "#     Generate recommendations for every experiment"
  	echo "######################################################"
  	echo
	curl -X POST "http://${KRUIZE_URL}/generateRecommendations?experiment_name=namespace-demo"
  	
	echo ""

  	echo
  	echo "######################################################"
  	echo
  	echo "Generate fresh recommendations using"
	echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=namespace-demo"
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

	pushd autotune >/dev/null
		# Checkout mvp_demo to get the latest mvp_demo release version
		git checkout mvp_demo >/dev/null 2>/dev/null

		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			sed -i 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_MINIKUBE}
		elif [ ${CLUSTER_TYPE} == "openshift" ]; then
			sed -i 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_OPENSHIFT}
		fi
	popd >/dev/null
}

#
#
#
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
		clone_repos benchmarks
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			check_minikube
			minikube >/dev/null
			check_err "ERROR: minikube not installed"
			minikube_start
			prometheus_install autotune
		fi
		benchmarks_install
	fi
	kruize_local_patch
	kruize_install
	echo

	get_urls

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
	else
		kruize_uninstall
	fi
	delete_repos autotune
	kubectl delete resourcequota default-quota -n test-multiple-import
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
elif [ ${start_demo} -eq 2 ]; then
	kruize_local_demo_update
else
	kruize_local_demo_terminate
fi
