#!/bin/bash
#
# Copyright (c) 2025, 2026 Red Hat, IBM Corporation and others.
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
common_dir="${current_dir}/../../../common/"
source ${common_dir}common_helper.sh
source ${current_dir}/../common.sh

# Default operator docker image repo
KRUIZE_OPERATOR_DOCKER_REPO="quay.io/kruize/kruize-operator"
export NAMESPACE="openshift-tuning"

# Default docker image repo
export KRUIZE_DOCKER_REPO="quay.io/kruize/autotune_operator"

# Default cluster
export CLUSTER_TYPE="kind"

# Target mode, default "crc"; "autotune" is currently broken
export target="crc"
export LOG_FILE="${current_dir}/kruize-demo.log"
KIND_IP=127.0.0.1
KRUIZE_PORT=8080
KRUIZE_UI_PORT=8081
TECHEMPOWER_PORT=8082
PETCLINIC_PORT=8083
KRUIZE_OPERATOR=1

function usage() {
	echo "Usage: $0 [-s|-t] [-c cluster-type] [-f] [-i kruize-image] [-u kruize-ui-image] [ [-b] [-m benchmark-manifests] [-n namespace] [-l] [-d load-duration] ] [-p] [-o kruize operator image] [-k]"
	echo "s = start (default), t = terminate"
	echo "c = supports minikube, kind and openshift cluster-type"
	echo "f = create environment setup if cluster-type is minikube, kind"
	echo "i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "o = Kruize operator image. Default - quay.io/kruize/kruize-operator:<version as in Makefile>"
	echo "b = deploy the benchmark."
	echo "m = manifests of the benchmark"
	echo "n = namespace of benchmark. Default - default"
	echo "l = Run a load against the benchmark"
	echo "d = duration to run the benchmark load"
	echo "p = expose prometheus port"
	echo "k = Disable operator and install kruize using deploy scripts instead."

	exit 1
}

# By default we start the demo and dont expose prometheus port
export DOCKER_IMAGES=""
export KRUIZE_DOCKER_IMAGE=""
export benchmark_load=0
export benchmark=0
export prometheus=0
export env_setup=0
export start_demo=1
export APP_NAMESPACE="default"
export LOAD_DURATION="1200"
export BENCHMARK_MANIFESTS="resource_provisioning_manifests"
export EXPERIMENT_TYPE=""
export KRUIZE_OPERATOR_IMAGE=""

# Iterate through the commandline options
while getopts bc:d:kfi:lm:no:pstu: gopts
do
	case "${gopts}" in
		b)
			start_demo=2
			benchmark=1
			;;
		c)
			CLUSTER_TYPE="${OPTARG}"
			;;
		d)
			LOAD_DURATION="${OPTARG}"
			;;
		f)
			env_setup=1
			;;
		i)
			KRUIZE_DOCKER_IMAGE="${OPTARG}"
			;;
		l)
			start_demo=2
			benchmark_load=1
			;;
		m)
			BENCHMARK_MANIFESTS="${OPTARG}"
			;;
		n)
			export APP_NAMESPACE="${OPTARG}"
			;;
		p)
			prometheus=1
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
		k)
			KRUIZE_OPERATOR=0
			;;
		*)
			usage
	esac
done

export EXPERIMENTS=("create_tfb-db_exp" "create_tfb_exp" "create_petclinic_openj9_exp")

if [[ "${CLUSTER_TYPE}" == "minikube" ]] || [[ "${CLUSTER_TYPE}" == "kind" ]]; then
	NAMESPACE="monitoring"
else
	NAMESPACE="openshift-tuning"
	export EXPERIMENTS=("create_tfb-db_exp_ocp" "create_tfb_exp_ocp" "create_petclinic_openj9_exp_ocp")
fi

BENCHMARK="tfb"
BENCHMARK2="petclinic"

export demo="runtimes"
if [ ${start_demo} -eq 1 ]; then
	echo > "${LOG_FILE}" 2>&1
	if [ ${KRUIZE_OPERATOR} -eq 1 ]; then
	  echo
	  # Check Go prerequisite before proceeding
	  check_go_prerequisite
	  check_err "ERROR: Go pre-requisite check failed. Cannot proceed with operator deployment."
	fi

	kruize_local_demo_setup ${BENCHMARK} ${KRUIZE_OPERATOR} ${BENCHMARK2}
	echo "For detailed logs, look in kruize-demo.log"
	echo
elif [ ${start_demo} -eq 2 ]; then
	kruize_local_demo_update ${BENCHMARK}
else
	echo >> "${LOG_FILE}" 2>&1
	kruize_local_demo_terminate
	echo "For detailed logs, look in kruize-demo.log"
	echo
fi
