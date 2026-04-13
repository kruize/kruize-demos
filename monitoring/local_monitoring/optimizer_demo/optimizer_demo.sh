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
	echo "p = Specify custom Kruize optimizer image: -p <image>. Default - quay.io/kruize/kruize-optimizer:<version as in Deployment File>"
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
export KRUIZE_OPTIMIZER_IMAGE="quay.io/kruize/kruize-optimizer:0.0.1"

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

# Set experiments for both sysbench and tfb
export EXPERIMENTS=("container_experiment_sysbench")
BENCHMARK="sysbench"
BENCHMARK2="tfb"

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

