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
current_dir="$(dirname "$0")"
common_dir="${current_dir}/../../../common/"
export CLUSTER_TYPE="openshift"
export KRUIZE_DOCKER_IMAGE="quay.io/kruize/autotune_operator:0.5"
# Define Kafka version and file URL
KAFKA_VERSION="3.9.0"
SCALA_VERSION="2.13"
KAFKA_TGZ="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
KAFKA_DIR="${current_dir}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}"
KAFKA_URL="https://dlcdn.apache.org/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}"
NAMESPACE="openshift-tuning"
KAFKA_NAMESPACE="kafka"
export target="crc"


start_demo=1
skip_namespace_reservation=0
repo_name=autotune
source "${common_dir}"/common_helper.sh
source "${current_dir}"/../common.sh

set -euo pipefail  # Enable strict error handling

LOG_FILE="${current_dir}/kafka-demo.log"

function usage() {
	echo "Usage: $0 [-s|-t] [-i kruize-image] [-u datasource-url] [-d datasource-name] [-c cluster-name] [-n namespace]"
	echo "s = start (default), t = terminate"
	echo "i = Kruize image (default: $KRUIZE_IMAGE)"
	echo "n = Namespace  (default: openshift-tuning)"
	echo "c = Cluster type (default: openshift)"
	exit 1
}

# Function to handle errors
error_exit() {
    echo "❌ Error: $1"
    exit 1
}

# Setup local kafka for message consumption
function setup_kafka_local() {
  KAFKA_ROOT_DIR=${PWD}

  if java -version &> /dev/null; then
      echo "Java is already installed."
      java -version
  else
      echo "Install java"
      exit 1
  fi

  # Check if the file exists
  if [ ! -f "$KAFKA_TGZ" ]; then
      echo "${KAFKA_TGZ} does not exist. Downloading..."
      wget -q ${KAFKA_URL}

      if [ $? -ne 0 ]; then
          echo "Failed to download $KAFKA_TGZ. Exiting."
          exit 1
      fi
  else
      echo "$KAFKA_TGZ already exists. Skipping download."
  fi

  echo "Extracting Kafka tgz..."
  tar zxf ${KAFKA_TGZ} -C ${KAFKA_ROOT_DIR}

  echo "Kafka setup completed!"
  echo
}

# Check if the cluster_type is one of icp or openshift
function check_cluster_type() {
	case "${CLUSTER_TYPE}" in openshift) ;;
	*)
		echo "Error: unsupported cluster type: ${CLUSTER_TYPE}"
		echo "Currently only openshift cluster is supported"
		exit -1
		;;
	esac
}

# Function to make API call and check response status
function api_call() {
    local url="$1"
    local data="$2"

    # Make API call and capture the HTTP response code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$data")

    # Check if response code is 200 or 201
    if [[ "$response_code" == "200" || "$response_code" == "201" ]]; then
        echo "✅ API call succeeded with response code: $response_code"
    elif [ "$response_code" == "409" ]; then
        echo "❌ API call failed with response code: $response_code"
        echo "Continuing to the next step..."
    else
        echo "❌ API call failed with response code: $response_code"
        exit 1
    fi
}

function kafka_demo_setup() {
	# Start all the installs
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "# Kafka Demo Setup on ${CLUSTER_TYPE} " | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo

	echo "Starting the bulk service..."

  # Switch to bulk_demo directory
  pushd ./../bulk_demo > /dev/null
  # Run the bulk service
  ./bulk_service_demo.sh -c "${CLUSTER_TYPE}" -i "${KRUIZE_DOCKER_IMAGE}"

  # Return back to the Kafka_demo directory
  popd > /dev/null
  echo
  echo "✅ Bulk Started Successfully!"

	echo -n "🔄 Exposing kruize service..."
	if ! oc expose svc/kruize 2>&1 | grep -q "AlreadyExists"; then
    echo "✅ Route created successfully!"
	else
			echo "⚠️ Route already exists, continuing..."
	fi
	########################
	# Get the route
	########################
	KRUIZE_ROUTE=$(oc get route | awk '$1 == "kruize" {print $2}')
	echo "KRUIZE_ROUTE = ${KRUIZE_ROUTE}" >> "${LOG_FILE}" 2>&1
	echo
	##########################################################################
	# Start consuming the recommendations using recommendations-topic
	##########################################################################
	echo -n "🔄 Setting up Kafka client locally to consume recommendations..."
  setup_kafka_local >> "${LOG_FILE}" 2>&1
  echo "✅ Kafka client setup completed"

  echo -n "🔄 Consuming recommendations from the recommendations-topic..."
  echo
  # get the certificate from the cluster
  oc get secret -n ${KAFKA_NAMESPACE} kruize-kafka-cluster-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt >> "${LOG_FILE}" 2>&1
  # save it as a java keystore file for the app to consume
  keytool -import -trustcacerts -alias root -file ca.crt -keystore truststore.jks -storepass password -noprompt >> "${LOG_FILE}" 2>&1
  # Grab Kafka Endpoint
  KAFKA_ENDPOINT=$(oc -n ${KAFKA_NAMESPACE} get kafka kruize-kafka-cluster -o=jsonpath='{.status.listeners[?(@.name=="route")].bootstrapServers}')

  # Consume messages from the recommendations-topic
  if command -v jq >/dev/null 2>&1; then
    ./${KAFKA_DIR}/bin/kafka-console-consumer.sh --bootstrap-server $KAFKA_ENDPOINT --topic recommendations-topic \
    --from-beginning --consumer-property security.protocol=SSL --consumer-property ssl.truststore.password=password \
    --consumer-property ssl.truststore.location=truststore.jks \
    --max-messages 1 | jq . || { echo "Error: Kafka consumer command failed!"; exit 1; }
  else
    echo "Warning: jq not found! Printing raw JSON."
    ./${KAFKA_DIR}/bin/kafka-console-consumer.sh --bootstrap-server $KAFKA_ENDPOINT --topic recommendations-topic \
    --from-beginning --consumer-property security.protocol=SSL --consumer-property ssl.truststore.password=password \
    --consumer-property ssl.truststore.location=truststore.jks \
    --max-messages 1 || { echo "Error: Kafka consumer command failed!"; exit 1; }
  fi
  echo -n "✅ Successfully consumed one recommendation from the recommendations topic"
	echo
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
	echo

	echo "✅"
	echo -n "🔄 Removing Kafka..."
	rm -rf ${KAFKA_TGZ} ${KAFKA_DIR}
	rm -rf ca.crt truststore.jks
	echo "✅ Done!"

	if [ -d autotune ]; then
    pushd autotune >/dev/null
      ./deploy.sh -c "${CLUSTER_TYPE}" -m ${target} -t  >> "${LOG_FILE}" 2>&1
      sleep 10
      check_err "ERROR: Failed to terminate kruize" | tee -a "${LOG_FILE}"
      echo
    popd >/dev/null
  fi
  #	echo -n "🔄 Removing git repos..."
  #	rm -rf ${repo_name}

	echo "For detailed logs, look in kafka-demo.log"
	echo
}

############################
#  Clone git Repos
############################
function clone_repo() {
  echo "1. Cloning ${repo_name} git repo..."
  if [ ! -d ${repo_name} ]; then
	  git clone git@github.com:kruize/"${repo_name}".git >/dev/null 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kruize/${repo_name}.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kruize/${repo_name} failed."
	fi
 	echo "done"
}


# Parse command-line options
while getopts "stc:i:u:d:r:n" opt; do
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
		KRUIZE_DOCKER_IMAGE="${OPTARG}"
		;;
	n)
    NAMESPACE="${OPTARG}"
		;;
	*)
		usage
		;;
	esac
done

# Perform action based on selection
if [ ${start_demo} -eq 1 ]; then
	echo
	echo "Starting the demo using: "
	echo "Kruize Image: $KRUIZE_DOCKER_IMAGE"
	echo "Namespace: $NAMESPACE"
	echo "Cluster: $CLUSTER_TYPE"
	kafka_demo_setup
else
	echo
	echo "🔄 Terminating the demo setup..."
	kafka_demo_setup_terminate
fi

# If the user passes '-h' or '--help', show usage and exit
if [[ $1 == "-h" || $1 == "--help" ]]; then
	usage
fi
