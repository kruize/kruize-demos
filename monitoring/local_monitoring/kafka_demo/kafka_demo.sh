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
KAFKA_CLUSTER_NAME="kruize-kafka-cluster"


APP_NAMESPACE="openshift-tuning"
KAFKA_NAMESPACE="kafka"
CERT_FILE="./ca.crt"
PASSWORD="password"

start_demo=1
bulk_demo=0
kafka_server_setup=0
repo_name=autotune

source "${common_dir}"/common_helper.sh
source "${current_dir}"/../common.sh

set -euo pipefail  # Enable strict error handling

LOG_FILE="${current_dir}/kafka-demo.log"

function usage() {
	echo "Usage: $0 [-s|-t] [-b] [-k] [-i kruize-image] [-c cluster-name] [-n kafka-namespace] [-a kruize-namespace]"
	echo "s = start (default), t = terminate"
	echo "b = start bulk_demo"
	echo "k = start kafka_server_setup"
	echo "i = Kruize image (default: $KRUIZE_DOCKER_IMAGE)"
	echo "a = Kruize Namespace  (default: openshift-tuning)"
	echo "n = Kafka Namespace  (default: kafka)"
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

function setup_kafka_server() {
  {
  # Create namespace for Kafka if it doesn't exist
  echo "Creating namespace for Kafka..."
  oc create namespace $KAFKA_NAMESPACE || echo "Namespace $KAFKA_NAMESPACE already exists."

  # Install Kafka using Strimzi Operator (if not already installed)
  echo "Installing Strimzi Operator..."
  oc apply -f https://strimzi.io/install/latest?namespace=$KAFKA_NAMESPACE -n $KAFKA_NAMESPACE

  # Wait for the Strimzi Operator to be ready
  echo "Waiting for Strimzi Operator to be ready..."
  oc rollout status deployment/strimzi-cluster-operator -n $KAFKA_NAMESPACE

  # Create Kafka cluster YAML
  cat <<EOF | oc apply -n $KAFKA_NAMESPACE -f -
  apiVersion: kafka.strimzi.io/v1beta2
  kind: Kafka
  metadata:
    name: $KAFKA_CLUSTER_NAME
  spec:
    kafka:
      version: 3.8.0
      replicas: 3
      listeners:
        - name: plain
          port: 9092
          type: internal
          tls: false
        - name: tls
          port: 9093
          type: internal
          tls: true
        - name: external
          port: 9094
          type: route
          tls: true
      config:
        offsets.topic.replication.factor: 3
        transaction.state.log.replication.factor: 3
        log.message.format.version: "3.4"
      storage:
        type: ephemeral
    zookeeper:
      replicas: 3
      storage:
        type: ephemeral
    entityOperator:
      topicOperator: {}
      userOperator: {}
EOF

  # Wait for Kafka to be ready
  echo "Waiting for Kafka cluster to be ready..."
  oc wait kafka/$KAFKA_CLUSTER_NAME --for=condition=Ready --timeout=300s -n $KAFKA_NAMESPACE

# Create Kafka topics
echo "Creating Kafka topics..."
cat <<EOF | oc apply -n $KAFKA_NAMESPACE -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: recommendations-topic
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  partitions: 3
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: error-topic
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  partitions: 3
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: summary-topic
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  partitions: 3
  replicas: 3
EOF

  # Get Kafka bootstrap server URL
  BOOTSTRAP_SERVER="$KAFKA_CLUSTER_NAME-kafka-bootstrap.$KAFKA_NAMESPACE.svc.cluster.local:9092"

  echo "✅ Kafka Bootstrap Server: $BOOTSTRAP_SERVER"
  export BOOTSTRAP_SERVER
  } >> "${LOG_FILE}" 2>&1
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

function kafka_server_cleanup() {
	{
    echo "Starting Kafka server cleanup process..."
    # Delete Kafka components first
    echo "Deleting Kafka resources..."
    oc delete kafka --all -n $KAFKA_NAMESPACE --ignore-not-found=true
    oc delete kafkatopic --all -n $KAFKA_NAMESPACE --ignore-not-found=true
    oc delete kafkauser --all -n $KAFKA_NAMESPACE --ignore-not-found=true
    oc delete kafkamirrormaker --all -n $KAFKA_NAMESPACE --ignore-not-found=true
    oc delete kafkamirrormaker2 --all -n $KAFKA_NAMESPACE --ignore-not-found=true
    oc delete kafkabridge --all -n $KAFKA_NAMESPACE --ignore-not-found=true
    oc delete kafkarebalance --all -n $KAFKA_NAMESPACE --ignore-not-found=true

    # Delete Strimzi Operator
    echo "Deleting Strimzi Operator..."
    oc delete deployment strimzi-cluster-operator -n $KAFKA_NAMESPACE --ignore-not-found=true

     # Remove stuck finalizers from Kafka CRDs
    echo "Checking for stuck Kafka CRDs..."
    for crd in kafkatopics kafkabridges kafkaconnectors kafkaconnects kafkamirrormaker2s kafkamirrormakers kafkanodepools kafkarebalances kafkas kafkausers; do
        oc get crd $crd.kafka.strimzi.io --ignore-not-found=true -o json | jq -r '.metadata.name' | while read line; do
            echo "Force deleting finalizer for: $line"
            oc patch crd $line -p '{"metadata":{"finalizers":[]}}' --type=merge || echo "Failed to patch $line"
        done
    done

    # Delete Kafka CRDs
    for crd in $(oc get crds -o json | jq -r '.items[].metadata.name' | grep 'kafka\|strimzi'); do
      echo "Deleting CRD: $crd"
      oc delete crd "$crd" --ignore-not-found=true
    done

    # Delete namespace
    echo "Deleting Kafka namespace..."
    oc delete namespace $KAFKA_NAMESPACE --ignore-not-found=true &

    # Wait for 30 seconds, then check if the namespace is still terminating
    sleep 30

    NAMESPACE_STATUS=$(oc get ns $KAFKA_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null)

    if [[ "$NAMESPACE_STATUS" == "Terminating" ]]; then
        echo "Namespace $KAFKA_NAMESPACE is stuck in Terminating state. Forcing deletion..."

        # Remove finalizers
        oc get ns $KAFKA_NAMESPACE -o json | jq 'del(.spec.finalizers)' | oc replace --raw "/api/v1/namespaces/$KAFKA_NAMESPACE/finalize" -f -

        # Delete any lingering terminating pods
        oc get pods -n $KAFKA_NAMESPACE | grep Terminating | awk '{print $1}' | xargs -r oc delete pod --grace-period=0 --force -n $KAFKA_NAMESPACE

        # Retry deleting the namespace
        oc delete ns $KAFKA_NAMESPACE --force --grace-period=0
    fi

    # Final check
    if oc get ns $KAFKA_NAMESPACE &>/dev/null; then
        echo "Namespace $KAFKA_NAMESPACE deletion failed. Please check manually."
    else
        echo "Namespace $KAFKA_NAMESPACE deleted successfully."
    fi

    echo "Kafka cleanup completed successfully!"


  } >> "${LOG_FILE}" 2>&1
}

function consume_messages() {
  {
    # get the certificate from the cluster
    oc get secret -n ${KAFKA_NAMESPACE} kruize-kafka-cluster-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
    # save it as a java keystore file for the app to consume
    keytool -import -trustcacerts -alias root -file ca.crt -keystore truststore.jks -storepass password -noprompt >> "${LOG_FILE}" 2>&1
    # Grab Kafka Endpoint
    KAFKA_ENDPOINT=$(oc -n ${KAFKA_NAMESPACE} get kafka kruize-kafka-cluster -o=jsonpath='{.status.listeners[?(@.name=="external")].bootstrapServers}')
    echo "$KAFKA_ENDPOINT" > /tmp/kafka_endpoint.txt
    echo "Kafka endpoint: $KAFKA_ENDPOINT"

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
  } >> "${LOG_FILE}" 2>&1
}

function show_urls() {
  LOG_FILE=${current_dir}/kafka-demo.log
  # Read Kafka endpoint from a temporary file (set by consume_messages)
  KAFKA_ENDPOINT=$(cat /tmp/kafka_endpoint.txt)

	echo "-------------------------------------------" >> "${LOG_FILE}" 2>&1
	echo "          CLI Commands for Kafka          " >> "${LOG_FILE}" 2>&1
	echo "-------------------------------------------" >> "${LOG_FILE}" 2>&1
	echo "1. Consume Single message from recommendations-topic :" >> "${LOG_FILE}" 2>&1
	echo " ./${KAFKA_DIR}/bin/kafka-console-consumer.sh --bootstrap-server $KAFKA_ENDPOINT --topic recommendations-topic \
      --from-beginning --consumer-property security.protocol=SSL --consumer-property ssl.truststore.password=password \
      --consumer-property ssl.truststore.location=truststore.jks \
      --max-messages 1 | jq ." >> "${LOG_FILE}" 2>&1
	echo >> "${LOG_FILE}" 2>&1
	echo "2. Consume all the messages from recommendations-topic :" >> "${LOG_FILE}" 2>&1
	echo " ./${KAFKA_DIR}/bin/kafka-console-consumer.sh --bootstrap-server $KAFKA_ENDPOINT --topic recommendations-topic \
      --from-beginning --consumer-property security.protocol=SSL --consumer-property ssl.truststore.password=password \
      --consumer-property ssl.truststore.location=truststore.jks | jq ." >> "${LOG_FILE}" 2>&1
	echo >> "${LOG_FILE}" 2>&1
	echo "3. Consume messages from error-topic :" >> "${LOG_FILE}" 2>&1
	echo " ./${KAFKA_DIR}/bin/kafka-console-consumer.sh --bootstrap-server $KAFKA_ENDPOINT --topic error-topic \
      --from-beginning --consumer-property security.protocol=SSL --consumer-property ssl.truststore.password=password \
      --consumer-property ssl.truststore.location=truststore.jks | jq ." >> "${LOG_FILE}" 2>&1
	echo >> "${LOG_FILE}" 2>&1
	echo "4. Consume message from summary-topic :" >> "${LOG_FILE}" 2>&1
	echo " ./${KAFKA_DIR}/bin/kafka-console-consumer.sh --bootstrap-server $KAFKA_ENDPOINT --topic summary-topic \
      --from-beginning --consumer-property security.protocol=SSL --consumer-property ssl.truststore.password=password \
      --consumer-property ssl.truststore.location=truststore.jks | jq ." >> "${LOG_FILE}" 2>&1
	echo >> "${LOG_FILE}" 2>&1
	echo "For kruize local documentation, refer https://github.com/kruize/autotune/blob/master/design/KruizeLocalAPI.md"  >> "${LOG_FILE}" 2>&1
	echo "For bulk documentation, refer https://github.com/kruize/autotune/blob/master/design/BulkAPI.md"  >> "${LOG_FILE}" 2>&1
	echo "For Kafka documentation, refer https://github.com/kruize/autotune/blob/master/design/KafkaDesign.md"  >> "${LOG_FILE}" 2>&1
}

function kafka_demo_setup() {
	# Start all the installs
	start_time=$(get_date)
	# Clear the log file at the start of the script
  > "${LOG_FILE}"

	{
    echo
    echo "#######################################"
    echo "# Kafka Demo Setup on ${CLUSTER_TYPE} "
    echo "#######################################"
    echo
  } | tee -a "${LOG_FILE}"

  rm -rf ca.crt truststore.jks >> "${LOG_FILE}" 2>&1

  if [ ${kafka_server_setup} -eq 1 ]; then
    echo -n "🔄 Setting up Kafka server on $CLUSTER_TYPE. Please wait..."
    kafka_start_time=$(get_date)
    setup_kafka_server &
    install_pid=$!
    while kill -0 $install_pid 2>/dev/null;
    do
      echo -n "."
      sleep 5
    done
    wait $install_pid
    status=$?
    if [ ${status} -ne 0 ]; then
      exit 1
    fi
    kafka_end_time=$(get_date)

    echo "✅ Kafka server setup completed"
  else
    echo "⏭️ Skipping Kafka Server installation..."
  fi
  echo
  export  BOOTSTRAP_SERVER="$KAFKA_CLUSTER_NAME-kafka-bootstrap.$KAFKA_NAMESPACE.svc.cluster.local:9092"

  if [ ${bulk_demo} -eq 1 ]; then
    echo "🔄 Starting the bulk service..."

    # Switch to bulk_demo directory
    pushd ./../bulk_demo > /dev/null
    # Run the bulk service
    ./bulk_service_demo.sh -c "${CLUSTER_TYPE}" -i "${KRUIZE_DOCKER_IMAGE}" -k

    # Return back to the Kafka_demo directory
    popd > /dev/null
    echo
  else
    echo "⏭️ Skipping bulk service initiation..."
    echo
  fi

	##########################################################################
	# Start consuming the recommendations using recommendations-topic
	##########################################################################
	echo -n "⏳ Setting up Kafka client locally to consume recommendations..."
  setup_kafka_local >> "${LOG_FILE}" 2>&1
  echo "✅ Kafka client setup completed"

  # consume kafka message
  echo -n "👀 Consuming recommendations from the recommendations-topic..."
  kafka_consumer_start_time=$(get_date)
  consume_messages &
  install_pid=$!
  while kill -0 $install_pid 2>/dev/null;
  do
    echo -n "."
    sleep 5
  done
  wait $install_pid
  status=$?
  if [ ${status} -ne 0 ]; then
    exit 1
  fi
  kafka_consumer_end_time=$(get_date)

  echo "✅ Done"
	echo

	end_time=$(get_date)
	if [ ${kafka_server_setup} -eq 1 ]; then
	  kafka_elapsed_time=$(time_diff "${kafka_start_time}" "${kafka_end_time}")
	  echo "🕒 Success! Kafka Server setup took ${kafka_elapsed_time} seconds"
	fi

  kafka_consumer_elapsed_time=$(time_diff "${kafka_consumer_start_time}" "${kafka_consumer_end_time}")
  echo "🕒 Success! Kafka Consumer took ${kafka_consumer_elapsed_time} seconds"

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

	echo -n "🔄 Removing Bulk Service..."
	# Switch to bulk_demo directory
  pushd ./../bulk_demo > /dev/null
  # Run the bulk service
  ./bulk_service_demo.sh -c "${CLUSTER_TYPE}" -t
  popd > /dev/null
	echo "✅ Done!"
	echo -n "🔄 Removing Kafka..."
	rm -rf ${KAFKA_TGZ} ${KAFKA_DIR}
	rm -rf $CERT_FILE truststore.jks
	kafka_server_cleanup
	echo "✅ Done!"

	if [ -d autotune ]; then
    pushd autotune >/dev/null
      ./deploy.sh -c "${CLUSTER_TYPE}" -m ${target} -t  >> "${LOG_FILE}" 2>&1
      sleep 10
      check_err "ERROR: Failed to terminate kruize" | tee -a "${LOG_FILE}"
      echo
    popd >/dev/null
  fi
  echo -n "🔄 Removing git repos..."
  rm -rf ${repo_name}

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
while getopts "stbkc:i:u:d:r:n:a" opt; do
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
    KAFKA_NAMESPACE="${OPTARG}"
		;;
  a)
    APP_NAMESPACE="${OPTARG}"
		;;
  b)
    bulk_demo=1
		;;
  k)
    kafka_server_setup=1
		;;
	*)
		usage
		;;
	esac
done

# Perform action based on selection
if [ ${start_demo} -eq 1 ]; then
	{
    echo
    echo "Starting the demo using: "
    echo "Kruize Image: $KRUIZE_DOCKER_IMAGE"
    echo "Kruize Namespace: $APP_NAMESPACE"
    echo "Kafka Namespace: $KAFKA_NAMESPACE"
    echo "Cluster: $CLUSTER_TYPE"
    echo "Bulk Demo: $bulk_demo"
    echo "Kafka Server Setup: $kafka_server_setup"
	} >> "${LOG_FILE}"
	kafka_demo_setup
	echo "For detailed logs, look in kafka-demo.log"
	show_urls
else
	echo
	echo "🔄 Terminating the demo setup..."
	kafka_demo_setup_terminate
  echo "For detailed logs, look in kafka-demo.log"
fi

# If the user passes '-h' or '--help', show usage and exit
if [[ $1 == "-h" || $1 == "--help" ]]; then
	usage
fi
