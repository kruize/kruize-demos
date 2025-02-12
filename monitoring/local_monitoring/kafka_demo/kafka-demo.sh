#!/bin/bash
#
# Copyright (c) 2025 Red Hat, IBM Corporation and others.
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

# Default values
CLUSTER_TYPE="ephemeral"
KRUIZE_IMAGE="quay.io/khansaad/autotune_operator"
KRUIZE_IMAGE_TAG="kafka"
DATASOURCE_URL="http://thanos-query-frontend-example-query-thanos-operator-system.apps.kruize-scalelab.h0b5.p1.openshiftapps.com/"
DATASOURCE_NAME="thanos-ee-2"
CLOWDAPP_FILE="./ros-ocp-backend/kruize-clowdapp.yaml"
BONFIRE_CONFIG="$HOME/.config/bonfire/config.yaml"
current_dir="$(dirname "$0")"
LOG_FILE="${current_dir}/kafka-demo.log"

start_demo=1
skip_setup=0
repo_name=ros-ocp-backend
common_dir="${current_dir}/../../../common/"

set -euo pipefail  # Enable strict error handling

source ${common_dir}/common_helper.sh
source ${current_dir}/../common.sh

function usage() {
	echo "Usage: $0 [-s|-t] [-i kruize-image] [-u datasource-url] [-d datasource-name]"
	echo "s = start (default), t = terminate"
	echo "i = Kruize image (default: $KRUIZE_IMAGE)"
	echo "c = Cluster type (default: ephemeral)"
	echo "u = Prometheus/Thanos datasource URL (default: $DATASOURCE_URL)"
	echo "d = Name of the datasource (default: $DATASOURCE_NAME)"
	exit 1
}

# Function to handle errors
error_exit() {
    echo "❌ Error: $1"
    exit 1
}

# Check if bonfire is installed
function check_bonfire() {
if ! command -v bonfire &>/dev/null; then
    error_exit "Bonfire tool is not installed. Please install it before running this script."
fi
}

# Check if the cluster_type is one of icp or openshift
function check_cluster_type() {
	case "${cluster_type}" in ephemeral) ;;
	*)
		echo "Error: unsupported cluster type: ${cluster_type}"
		echo "Currently only ephemeral cluster is supported"
		exit -1
		;;
	esac
}

# replace the kruize-clowder file in the repo with the local one
function clowder_file_replace() {
	echo "🔄 Replacing 'kruize-clowdapp' in the cloned repo..."
	cp "./kruize-clowdapp.yaml" "$repo_name/kruize-clowdapp.yaml"  || { echo "❌ Failed to replace the file."; exit 1; }
	echo "✅ File replaced successfully!"
}

function kafka_demo_setup() {
	# Start all the installs
	start_time=$(get_date)
	check_bonfire
#	if [ ${skip_setup} -eq 0 ]; then
		echo | tee -a "${LOG_FILE}"
		echo "#######################################" | tee -a "${LOG_FILE}"
		echo "# Kafka Demo Setup on ${CLUSTER_TYPE} " | tee -a "${LOG_FILE}"
		echo "#######################################" | tee -a "${LOG_FILE}"
		echo

		echo -n "🔄 Reserving a namespace... "
		{
			bonfire namespace reserve -d 24h
			EPHEMERAL_NAMESPACE=$(bonfire namespace list --mine | awk 'NR==3 {print $1}')
		} >>"${LOG_FILE}" 2>&1
		echo "✅ Done!"
		echo -n "🔄 Updating Bonfire config with the Kruize image..."
		{
			if [[ -f "$BONFIRE_CONFIG" ]]; then
				echo "Updating Bonfire config file: $BONFIRE_CONFIG..."

				# Update KRUIZE_IMAGE
				if grep -q "KRUIZE_IMAGE:" "$BONFIRE_CONFIG"; then
					sed -i "s|KRUIZE_IMAGE:.*|KRUIZE_IMAGE: $KRUIZE_IMAGE|" "$BONFIRE_CONFIG"
				fi

				# Update KRUIZE_IMAGE_TAG
				if grep -q "KRUIZE_IMAGE_TAG:" "$BONFIRE_CONFIG"; then
					sed -i "s|KRUIZE_IMAGE_TAG:.*|KRUIZE_IMAGE_TAG: $KRUIZE_IMAGE_TAG|" "$BONFIRE_CONFIG"
				fi
			else
				echo "Error: Bonfire config.yaml file not found. Skipping update."
			fi
		} >>"${LOG_FILE}" 2>&1
		echo "✅ Done!"
		echo -n "🔄 Pulling required repositories..."
		if [ ! -d ${repo_name} ]; then
			{
				clone_repo
			} >>"${LOG_FILE}" 2>&1
		fi
		echo "✅ Done!"
		# below step is temporarily added, will be removed once the kruize-clowdapp changes are merged
		clowder_file_replace
#	fi
	echo "EPHEMERAL_NAMESPACE = ${EPHEMERAL_NAMESPACE}"
	########################
	# Get Kafka svc
	########################
	KAFKA_SVC_NAME=$(oc get svc | grep kafka-bootstrap | awk '{print $1}')

	#######################################################################################
	# Modify kruize-clowdapp file to update the namespace and kafka bootstrap value
	#######################################################################################

	if [[ -f "$CLOWDAPP_FILE" ]]; then
		echo -n "🔄 Modifying $CLOWDAPP_FILE..."

		# Update the namespace value in the YAML file
		sed -i "s/\(http:\/\/kruize-recommendations\.\)ephemeral-[a-z0-9]\+\(.*\)/\1${EPHEMERAL_NAMESPACE}\2/" "$CLOWDAPP_FILE"

		# Update KAFKA_BOOTSTRAP_SERVERS value
		sed -i "s/\(value: \"\)env-ephemeral-[a-z0-9]\+-[a-z0-9]\+-kafka-bootstrap\(\..*\)/\1${KAFKA_SVC_NAME}\2/" "$CLOWDAPP_FILE"
		sed -i "s/\(value: \".*\)ephemeral-[a-z0-9]\+\(.*\)/\1${EPHEMERAL_NAMESPACE}\2/" "$CLOWDAPP_FILE"
		echo "✅ Done!"
	else
		echo "Error: $CLOWDAPP_FILE not found. Skipping modification."
	fi

	echo -n "🔄 Deploying the application.Please wait..."
	{
		bonfire deploy ros-ocp-backend -C kruize-test
	} >>"${LOG_FILE}" 2>&1
	echo "✅ Installation complete!"

	############################
	# Expose Kruize svc
	############################
	echo "🔄 Exposing kruize-recommendations service..."
	oc expose svc/kruize-recommendations || error_exit "Failed to expose kruize-recommendations service."
	echo "✅ Done!"


	########################
	# Get the route
	########################
	KRUIZE_ROUTE=$(oc get route | grep kruize-recommendations-ephemeral | awk '{print $2}')
	echo "KRUIZE_ROUTE = ${KRUIZE_ROUTE}"

	################################
	# Create Metric Profile
	################################
	echo -n "🔄 Creating Metric Profile..."
	curl -X POST "http://${KRUIZE_ROUTE}/createMetricProfile" -d @resource_optimization_local_monitoring.json || error_exit "Failed to send createMetricProfile request."
	echo "✅ Created Successfully!"

	####################################################
	# Invoke the Bulk Service and get the jobID
	####################################################
	echo "🔄 Invoking Bulk Service..."
	echo "curl -s -X POST "${KRUIZE_ROUTE}/bulk" -H Content-Type: application/json -d '{\"datasource\":\"${DATASOURCE_NAME}\"}'"
	curl -s -X POST "http://${KRUIZE_ROUTE}/bulk" -H "Content-Type: application/json" -d "{\"datasource\":\"${DATASOURCE_NAME}\"}" || error_exit "Failed to send bulk request."
	echo "✅ Job_id generated!"

	##########################################################################
	# Start consuming the recommendations using recommendations-topic
	##########################################################################
	echo -n "🔄 Consuming recommendations from recommendations-topic..."
	echo
	KAFKA_POD_NAME=$(oc get pods | grep kafka | awk '{print $1}')
	echo "KAFKA_POD_NAME = ${KAFKA_POD_NAME}"
	echo "KAFKA_SVC_NAME = ${KAFKA_SVC_NAME}"
	echo "EPHEMERAL_NAMESPACE = ${EPHEMERAL_NAMESPACE}"
	echo "oc exec "$KAFKA_POD_NAME" -- bin/kafka-console-consumer.sh --topic recommendations-topic --bootstrap-server "${KAFKA_SVC_NAME}"."${EPHEMERAL_NAMESPACE}".svc.cluster.local:9092"
	oc exec $KAFKA_POD_NAME -- bin/kafka-console-consumer.sh --topic recommendations-topic --bootstrap-server ${KAFKA_SVC_NAME}.${EPHEMERAL_NAMESPACE}.svc.cluster.local:9092

	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "🕒 Success! Kafka demo setup took ${elapsed_time} seconds"
	echo
}

function kafka_demo_setup_terminate() {
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "#  Kafka Demo Terminate on ${CLUSTER_TYPE} #" | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"
	echo "Clean up in progress..."

	if [ "${CLUSTER_TYPE}" == "ephemeral" ]; then
		bonfire namespace release -f
	fi
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo
	echo "🕒 Success! Kafka demo cleanup took ${elapsed_time} seconds"
	echo
}

############################
#  Clone git Repos
############################
function clone_repo() {
	echo "1. Cloning ${repo_name} git repo..."
	git clone git@github.com:RedHatInsights/"${repo_name}".git >/dev/null 2>/dev/null
	check_err "ERROR: git clone of ros-ocp-backend failed."
	echo "done"
}

# Parse command-line options
while getopts "sti:u:d:r" opt; do
	case "${opt}" in
	s)
		start_demo=1
		;;
	t)
		start_demo=0
		;;
	c)
		CLUSTER_TYPE="${OPTARG}"
		check_cluster_type
		;;
	i)
		IFS=":" read -r KRUIZE_IMAGE KRUIZE_IMAGE_TAG <<<"${OPTARG}"
		;;
	u)
		DATASOURCE_URL="${OPTARG}"
		;;
	d)
		DATASOURCE_NAME="${OPTARG}"
		;;
	r)
		skip_setup=1
		;;
	*)
		usage
		;;
	esac
done

echo "Kruize Image: $KRUIZE_IMAGE"
echo "Kruize Image Tag: $KRUIZE_IMAGE_TAG"
echo "DATASOURCE_URL: $DATASOURCE_URL"
echo "DATASOURCE_NAME: $DATASOURCE_NAME"

# Perform action based on selection
if [ ${start_demo} -eq 1 ]; then
	echo
	echo "Starting deployment..."
	kafka_demo_setup
elif [ ${start_demo} -eq 0 ]; then
	echo
	echo "Terminating deployment..."
	kafka_demo_setup_terminate
else
	echo "Invalid action!"
	usage
fi

# If the user passes '-h' or '--help', show usage and exit
if [[ $1 == "-h" || $1 == "--help" ]]; then
	usage
fi
