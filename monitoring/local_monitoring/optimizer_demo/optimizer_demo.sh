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
current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
common_dir="${current_dir}/../../../common/"
local_monitoring_dir="${current_dir}/.."
source ${common_dir}common_helper.sh
source ${local_monitoring_dir}/common.sh

# Default operator docker image repo
KRUIZE_OPERATOR_DOCKER_REPO="quay.io/kruize/kruize-operator"

# Default docker image repo
export KRUIZE_DOCKER_REPO="quay.io/kruize/autotune_operator"

# Default cluster
export CLUSTER_TYPE="kind"

# Target mode
export target="crc"
export LOG_FILE="${current_dir}/optimizer-demo.log"
KIND_IP=127.0.0.1
KRUIZE_PORT=8080
KRUIZE_UI_PORT=8081
KRUIZE_OPERATOR=1

function usage() {
	echo "Usage: $0 [-s|-t] [-c cluster-type] [-f] [-i kruize-image] [-u kruize-ui-image] [-o kruize-operator-image] [-p optimizer-image] [-n namespace] [-k]"
	echo "s = start (default), t = terminate"
	echo "c = supports minikube, kind and openshift cluster-type"
	echo "f = create environment setup if cluster-type is minikube, kind"
	echo "i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "o = Specify custom Kruize operator image: -o <image>. Default - quay.io/kruize/kruize-operator:<version as in Makefile>"
	echo "p = Specify custom Kruize optimizer image: -p <image>."
	echo "n = namespace of benchmark. Default - default"
	echo "k = Disable operator and install kruize using deploy scripts instead."

	exit 1
}

# By default we start the demo
export DOCKER_IMAGES=""
export KRUIZE_DOCKER_IMAGE=""
export env_setup=0
export start_demo=1
export APP_NAMESPACE="default"
export KRUIZE_OPERATOR_IMAGE=""
export KRUIZE_OPTIMIZER_IMAGE=""

# Iterate through the commandline options
while getopts c:fi:kn:o:p:stu: gopts
do
	case "${gopts}" in
		c)
			CLUSTER_TYPE="${OPTARG}"
			;;
		f)
			env_setup=1
			;;
		i)
			KRUIZE_DOCKER_IMAGE="${OPTARG}"
			;;
		n)
			export APP_NAMESPACE="${OPTARG}"
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
		o)
			KRUIZE_OPERATOR_IMAGE="${OPTARG}"
			;;
		p)
			KRUIZE_OPTIMIZER_IMAGE="${OPTARG}"
			;;
		k)
		    KRUIZE_OPERATOR=0
		    ;;
		*)
			usage
	esac
done

export demo="optimizer"

if [[ "${CLUSTER_TYPE}" == "minikube" ]] || [[ "${CLUSTER_TYPE}" == "kind" ]]; then
    NAMESPACE="monitoring"
else
    NAMESPACE="openshift-tuning"
fi

# Set experiment for sysbench
export EXPERIMENTS=("container_experiment_sysbench")
BENCHMARK="sysbench"

function optimizer_demo_setup() {
	bench=$1
	kruize_operator=$2
	
	# Start all the installs
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "# Kruize Optimizer Demo Setup on ${CLUSTER_TYPE} " | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo

	# Clone repos first if not already present (needed for cleanup functions)
	if [ ! -d "${local_monitoring_dir}/autotune" ]; then
		echo -n "🔄 Pulling required repositories... "
		{
			cd ${local_monitoring_dir}
			clone_repos autotune
			clone_repos benchmarks
		} >> "${LOG_FILE}" 2>&1
		echo "✅ Done!"
	fi

	# Check for both operator and kruize deployments
	echo -n "🔍 Checking if Kruize deployment is running..."
	
	# First check if cluster is accessible with timeout
	cluster_accessible=false
	if timeout 5 kubectl cluster-info &>/dev/null; then
		cluster_accessible=true
	fi

	operator_exists=false
	kruize_exists=false

	# Only check for existing deployments if cluster is accessible
	if [ "$cluster_accessible" = true ]; then
		# Check for operator deployment
		operator_deployment=$(kubectl get deployment kruize-operator -n ${NAMESPACE} 2>&1)

		# Check for kruize pods
		kruize_pods=$(kubectl get pod -l app=kruize -n ${NAMESPACE} 2>&1)

		if [[ ! "$operator_deployment" =~ "NotFound" ]] && [[ ! "$operator_deployment" =~ "No resources" ]]; then
			operator_exists=true
		fi

		if [[ ! "$kruize_pods" =~ "NotFound" ]] && [[ ! "$kruize_pods" =~ "No resources" ]]; then
			kruize_exists=true
		fi
	fi
	
	if [ "$operator_exists" = true ] || [ "$kruize_exists" = true ]; then
		echo " Found!"
		echo -n "🔄 Cleaning up existing Kruize deployment (including database)..."
		{
		  	# Kill existing port-forwards before cleanup (only for kind cluster)
	   		if [ ${CLUSTER_TYPE} == "kind" ]; then
				kill_service_port_forward "kruize"
				kill_service_port_forward "kruize-ui-nginx-service"
	   		fi

			# Run operator cleanup if operator exists
			if [ "$operator_exists" = true ]; then
				kruize_operator_cleanup $NAMESPACE
			fi
			
			# Check if kruize pods still exist and call kruize_uninstall if needed (only if cluster is accessible)
			if [ "$cluster_accessible" = true ]; then
				kruize_pods_after=$(kubectl get pod -l app=kruize -n ${NAMESPACE} 2>&1)
			else
				kruize_pods_after="Error: cluster not accessible"
			fi
			if [[ ! "$kruize_pods_after" =~ "NotFound" ]] && [[ ! "$kruize_pods_after" =~ "No resources" ]] && [[ ! "$kruize_pods_after" =~ "Error" ]]; then
				kruize_uninstall
			fi
		} >> "${LOG_FILE}" 2>&1
		echo "✅ Cleanup complete!"
		
		# Wait for cleanup to complete and resources to be fully removed
		echo -n "⏳ Waiting for resources to be fully removed..."
		sleep 10
		echo " Done!"
	else
		echo " Not running."
	fi

	if [[ ${env_setup} -eq 1 ]]; then
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			echo -n "🔄 Installing minikube and prometheus! Please wait..."
			check_minikube
			minikube >/dev/null
			check_err "ERROR: minikube not installed"
			minikube_start
			cd ${local_monitoring_dir}
			prometheus_install autotune
			echo "✅ Installation of minikube and prometheus complete!"
		elif [ ${CLUSTER_TYPE} == "kind" ]; then
			echo -n "🔄 Installing kind and prometheus! Please wait..."
			check_kind
			kind >/dev/null
			check_err "ERROR: kind not installed"
			kind_start
			cd ${local_monitoring_dir}
			prometheus_install
			echo "✅ Installation of kind and prometheus complete!"
		fi
	elif [[ ${env_setup} -eq 0 ]]; then
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			echo -n "🔄 Checking if minikube exists..."
			check_minikube
			minikube >/dev/null
			check_err "ERROR: minikube is not available. Please install and try again!"
			echo "✅ minikube exists!"
		elif [ ${CLUSTER_TYPE} == "kind" ]; then
			echo -n "🔄 Checking if kind exists..."
			check_kind
			kind >/dev/null
			check_err "ERROR: kind is not available. Please install and try again!"
			echo "✅ kind exists!"
		fi
	fi

	# Install sysbench benchmark
	echo -n "🔄 Installing sysbench benchmark..."
	cd ${local_monitoring_dir}
	create_namespace ${APP_NAMESPACE} >> "${LOG_FILE}" 2>&1
	# Clean up any existing sysbench deployment
	echo "Cleaning up any old sysbench deployment..." >> "${LOG_FILE}" 2>&1
	kubectl delete deployment sysbench -n ${APP_NAMESPACE} --ignore-not-found >> "${LOG_FILE}" 2>&1
	
	benchmarks_install ${APP_NAMESPACE} ${bench} "kruize-demos" >> "${LOG_FILE}" 2>&1
	echo "✅ Completed!"

	# Add label to sysbench deployment for auto-experiment creation
	sysbench_label="kruize/autotune=enabled"
	if [[ ${CLUSTER_TYPE} == "minikube" ]] || [[ ${CLUSTER_TYPE} == "kind" ]]; then
		echo -n "🔄 Adding kruize/autotune=enabled label to sysbench deployment..."
		# Label the deployment so all pods get the label
		kubectl label deployment sysbench "${sysbench_label}" -n ${APP_NAMESPACE} --overwrite >> "${LOG_FILE}" 2>&1
		echo -n "🔄 Enabling kube state metrics labels..."
		cd ${local_monitoring_dir}
		./autotune/scripts/enable_kube_state_metrics_labels.sh >> "${LOG_FILE}" 2>&1
		echo "✅ Complete!"
	else
		echo -n "🔄 Adding kruize/autotune=enabled label to sysbench deployment..."
		# Label the deployment so all pods get the label
		oc label deployment sysbench "${sysbench_label}" -n ${APP_NAMESPACE} --overwrite >> "${LOG_FILE}" 2>&1
		echo "✅ Complete!"
		echo -n "🔄 Enabling user workload monitoring..."
		cd ${local_monitoring_dir}
		./autotune/scripts/enable_user_workload_monitoring_openshift.sh >> "${LOG_FILE}" 2>&1
		echo "✅ Complete!"
	fi
	echo "" >> "${LOG_FILE}" 2>&1

	cd ${local_monitoring_dir}
	kruize_local_patch >> "${LOG_FILE}" 2>&1

	echo -n "🔄 Installing Kruize! Please wait..."
	kruize_start_time=$(get_date)
	if [[ "${kruize_operator}" -eq 1 ]]; then
		operator_setup >> "${LOG_FILE}" 2>&1 &
	else
		kruize_install >> "${LOG_FILE}" 2>&1 &
	fi
	
	# Wait for kruize installation
	wait
	echo " ✅ Kruize Installation Done!"
	
	# Install optimizer if not using operator
	if [[ "${kruize_operator}" -eq 0 ]]; then
		echo -n "🔄 Installing Optimizer! Please wait..."
		kruize_optimizer_install >> "${LOG_FILE}" 2>&1 &
		wait
		echo " ✅ Optimizer Installation Done!"
	fi
	
	# Check if kruize-optimizer pod is running
	echo -n "🔄 Verifying kruize-optimizer pod status..."
	max_attempts=12
	attempt=0
	while [ $attempt -lt $max_attempts ]; do
		if kubectl get pods -n ${NAMESPACE} -l app=kruize-optimizer --no-headers 2>/dev/null | grep -q "Running"; then
			echo " ✅ Optimizer is Running!"
			break
		fi
		if [ $attempt -eq $((max_attempts - 1)) ]; then
			echo " ❌ Failed!"
			echo "Kruize-optimizer pod is not running. Check logs for details."
			kubectl get pods -n ${NAMESPACE} -l app=kruize-optimizer
			exit 1
		fi
		echo -n "."
		sleep 5
		attempt=$((attempt + 1))
	done
	
	kruize_end_time=$(get_date)
	echo "✅ Kruize installation complete!"

	# Get the Kruize URL
	cd ${local_monitoring_dir}
	get_urls ${BENCHMARK} ${KRUIZE_OPERATOR}
	
	# Port forward the URLs in case of kind
	if [ ${CLUSTER_TYPE} == "kind" ]; then
		port_forward "${BENCHMARK}"
	fi
	
	echo "✅ Kruize is available at http://${KRUIZE_URL}"

	# Wait for Kruize to be ready
	echo -n "⏳ Waiting for Kruize to be ready..."
	max_attempts=60
	attempt=0
	while [ $attempt -lt $max_attempts ]; do
		if curl -s "http://${KRUIZE_URL}/health" > /dev/null 2>&1; then
			echo " ✅ Ready!"
			break
		fi
		echo -n "."
		sleep 5
		attempt=$((attempt + 1))
	done

	if [ $attempt -ge $max_attempts ]; then
		echo " ⚠️  Timeout waiting for Kruize to be ready"
	fi

	echo -n "⏳ Waiting for optimizer to create experiments (60s) ..."
	sleep 60
	echo " ✅ Done!"

	# Check for specific experiment
	EXPECTED_EXP="prometheus-1|default|default|sysbench(deployment)|sysbench"
	echo
	echo "######################################################"
	echo "#     Checking for Experiment"
	echo "######################################################"
	echo -n "🔍 Looking for experiment: ${EXPECTED_EXP}..."
	
	experiment_check=$(curl -s "http://${KRUIZE_URL}/listExperiments?experiment_name=${EXPECTED_EXP}")
	
	{
		echo
		echo "curl http://${KRUIZE_URL}/listExperiments?experiment_name=${EXPECTED_EXP}"
		echo $experiment_check | jq '.'
	} >> "${LOG_FILE}" 2>&1
	
	if echo "$experiment_check" | jq -e '.[0].experiment_name' > /dev/null 2>&1; then
		echo " ✅ Found!"
		echo
		echo "📋 Experiment Details:"
		echo "$experiment_check" | jq -r '.[0] | "   Name: \(.experiment_name)\n"'
		
		# List recommendations
		echo
		echo "######################################################"
		echo "#     Listing Recommendations"
		echo "######################################################"
		echo -n "🔄 Listing recommendations for ${EXPECTED_EXP}...\n"
		
		recommendations=$(curl -s "http://${KRUIZE_URL}/listRecommendations?experiment_name=${EXPECTED_EXP}")
		{
			echo
			echo "curl http://${KRUIZE_URL}/listRecommendations?experiment_name=${EXPECTED_EXP}"
			echo $recommendations | jq '.'
		} >> "${LOG_FILE}" 2>&1
		
		echo "📊 Recommendations for ${EXPECTED_EXP} (We need at least two data points (15 mins) to generate recommendations):"
		echo
		echo "$recommendations" | jq -r '
			if type == "array" and length > 0 then
				.[0].kubernetes_objects[0].containers[0] |
				"Container: \(.container_name)\n" +
				"Current Resources:\n" +
				"  CPU Request: \(.recommendations.data."2024-01-01T00:00:00.000Z".current.requests.cpu // "N/A")\n" +
				"  Memory Request: \(.recommendations.data."2024-01-01T00:00:00.000Z".current.requests.memory // "N/A")\n" +
				"Recommended Resources:\n" +
				"  CPU Request: \(.recommendations.data."2024-01-01T00:00:00.000Z".recommendation_terms.short_term.recommendations.requests.cpu // "N/A")\n" +
				"  Memory Request: \(.recommendations.data."2024-01-01T00:00:00.000Z".recommendation_terms.short_term.recommendations.requests.memory // "N/A")"
			else
				"No recommendations available yet. Try again in a few minutes."
			end
		' 2>/dev/null || echo "⚠️  Recommendations not ready yet. Check logs for details."
	else
		echo " ⚠️  Not found!"
		echo
		echo "⚠️  Expected experiment not found."
		
	fi

	echo "######################################################"
	echo

	cd ${local_monitoring_dir}
	show_urls ${bench}

	end_time=$(get_date)
	kruize_elapsed_time=$(time_diff "${kruize_start_time}" "${kruize_end_time}")
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "🛠️ Kruize installation took ${kruize_elapsed_time} seconds"
	echo "🕒 Success! Kruize optimizer demo setup took ${elapsed_time} seconds"
	echo
	echo "📝 Note: This demo installs Kruize optimizer and sysbench workload with labels."
	echo "📝 Experiments are auto-created by the optimizer for labelled workloads, use lable - kruize/autotune=enabled."
	echo "📝 Use the listExperiments API or Kruize UI to see created experiments."
}

function optimizer_demo_terminate() {
	kruize_operator=$1
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "#  Kruize Optimizer Demo Terminate on ${CLUSTER_TYPE} #" | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"
	echo "Clean up in progress..."

	cd ${local_monitoring_dir}

	if [[ "${kruize_operator}" -eq 1 ]]; then
		kruize_operator_cleanup $NAMESPACE >> "${LOG_FILE}" 2>&1
	fi

	kruize_uninstall >> "${LOG_FILE}" 2>&1
	
	# Uninstall kruize-optimizer
	kruize_optimizer_uninstall >> "${LOG_FILE}" 2>&1

	# Check if cluster is accessible before running kubectl commands with timeout
	if timeout 5 kubectl cluster-info &>/dev/null; then
		if kubectl get pods -n "${APP_NAMESPACE}" 2>/dev/null | grep -q "sysbench"; then
			benchmarks_uninstall ${APP_NAMESPACE} "sysbench" >> "${LOG_FILE}" 2>&1
		fi
	fi
	
	if [[ ${APP_NAMESPACE} != "default" ]]; then
		delete_namespace ${APP_NAMESPACE} >> "${LOG_FILE}" 2>&1
	fi

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube_delete >> "${LOG_FILE}" 2>&1
	elif [ ${CLUSTER_TYPE} == "kind" ]; then
		kill_service_port_forward "kruize"
		kill_service_port_forward "kruize-ui-nginx-service"
		kind_delete >> "${LOG_FILE}" 2>&1
	fi

	{
		delete_repos autotune
		delete_repos "benchmarks"
		delete_repos "kruize-operator"
		delete_repos "kruize-optimizer"
	} >> "${LOG_FILE}" 2>&1
	
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "🕒 Success! Kruize optimizer demo cleanup took ${elapsed_time} seconds"
}

###########################################
# Uninstall kruize-optimizer
###########################################
function kruize_optimizer_uninstall() {
	echo "🔄 Uninstalling kruize-optimizer"
	
	if [ -d "${local_monitoring_dir}/kruize-optimizer" ]; then
		cd ${local_monitoring_dir}/kruize-optimizer
		
		# Determine which overlay to use based on cluster type
		if [ "${CLUSTER_TYPE}" == "openshift" ]; then
			OVERLAY="openshift"
		else
			OVERLAY="kind"
		fi
		
		echo "📄 Deleting kruize-optimizer deployment using kustomize overlay: ${OVERLAY}"
		kubectl delete -k "deployment/overlays/${OVERLAY}" --ignore-not-found=true >> "${LOG_FILE}" 2>&1
		echo "✅ kruize-optimizer uninstallation complete!"
	else
		echo "⚠️  kruize-optimizer directory not found, skipping..."
	fi
}

###########################################
# Install kruize-optimizer
###########################################
function kruize_optimizer_install() {
	echo
	echo "🔄 Installing kruize-optimizer"
	
	# Clone kruize-optimizer repo if not present
	if [ ! -d "${local_monitoring_dir}/kruize-optimizer" ]; then
		echo "📥 Cloning kruize-optimizer repository (mvp_demo branch)..."
		cd ${local_monitoring_dir}
		git clone -b mvp_demo https://github.com/kruize/kruize-optimizer.git >> "${LOG_FILE}" 2>&1
		check_err "ERROR: Failed to clone kruize-optimizer repository"
	fi
	
	cd ${local_monitoring_dir}/kruize-optimizer
	
	# Update optimizer image if custom image is provided
	if [ -n "${KRUIZE_OPTIMIZER_IMAGE}" ]; then
		echo "🔧 Updating kruize-optimizer image to: ${KRUIZE_OPTIMIZER_IMAGE}"
		sed -i.bak "s|image: .*|image: ${KRUIZE_OPTIMIZER_IMAGE}|" deployment/base/deployment.yaml
	fi
	
	# Determine which overlay to use based on cluster type
	if [ "${CLUSTER_TYPE}" == "openshift" ]; then
		OVERLAY="openshift"
	else
		OVERLAY="kind"
	fi
	
	echo "📄 Applying kruize-optimizer deployment using kustomize overlay: ${OVERLAY}"
	kubectl apply -k "deployment/overlays/${OVERLAY}" >> "${LOG_FILE}" 2>&1
	check_err "ERROR: Failed to apply kruize-optimizer deployment"
	
	echo "⏳ Waiting for kruize-optimizer pod to be ready..."
	kubectl wait --for=condition=Ready pod -l app=kruize-optimizer -n ${NAMESPACE} --timeout=300s >> "${LOG_FILE}" 2>&1
	if [ $? -ne 0 ]; then
		echo "❌ kruize-optimizer pod failed to become ready"
		kubectl get pods -n ${NAMESPACE} -l app=kruize-optimizer
		kubectl describe pod -l app=kruize-optimizer -n ${NAMESPACE}
		exit 1
	fi
	
	echo "✅ kruize-optimizer installation complete!"
	sleep 5
}

if [ ${start_demo} -eq 1 ]; then
	echo > "${LOG_FILE}" 2>&1
	if [ ${KRUIZE_OPERATOR} -eq 1 ]; then
		echo
		# Check Go prerequisite before proceeding
		check_go_prerequisite
		check_err "ERROR: Go pre-requisite check failed. Cannot proceed with operator deployment."
	fi

	optimizer_demo_setup ${BENCHMARK} ${KRUIZE_OPERATOR}
	echo "For detailed logs, look in optimizer-demo.log"
	echo
else
	echo >> "${LOG_FILE}" 2>&1
	optimizer_demo_terminate ${KRUIZE_OPERATOR}
	echo "For detailed logs, look in optimizer-demo.log"
	echo
fi

