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
	echo "Usage: $0 [-s|-t] [-c cluster-type] [-f] [-i kruize-image] [-u kruize-ui-image] [ [-n namespace] ] [-p] [-o kruize operator image] [-k] [--branch branch] [--autotune-branch branch] [--operator-branch branch] [--optimizer-branch branch] [--benchmarks-branch branch]"
	echo "s = start (default), t = terminate"
	echo "c = supports minikube, kind and openshift cluster-type"
	echo "f = create environment setup if cluster-type is minikube, kind"
	echo "i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "o = Kruize operator image. Default - quay.io/kruize/kruize-operator:<version as in Makefile>"
	echo "n = namespace of benchmark. Default - default"
	echo "p = expose prometheus port"
	echo "k = Disable operator and install kruize using deploy scripts instead."
	echo "--branch = Branch name to use for all cloned repositories."
	echo "--autotune-branch = Kruize/Autotune git repo branch. Default - mvp_demo"
	echo "--operator-branch = Kruize operator git repo branch. Default - mvp_demo"
	echo "--optimizer-branch = Kruize optimizer git repo branch. Default - mvp_demo"
	echo "--benchmarks-branch = Benchmarks git repo branch."

	exit 1
}

# By default we start the demo and dont expose prometheus port
export DOCKER_IMAGES=""
export KRUIZE_DOCKER_IMAGE=""
export prometheus=0
export env_setup=0
export start_demo=1
export APP_NAMESPACE="default"
export BENCHMARK_MANIFESTS="kruize-demos"
export EXPERIMENT_TYPE=""
export KRUIZE_OPERATOR_IMAGE=""

# Default git branches
export AUTOTUNE_BRANCH="${AUTOTUNE_BRANCH:-mvp_demo}"
export KRUIZE_OPERATOR_BRANCH="${KRUIZE_OPERATOR_BRANCH:-mvp_demo}"
export KRUIZE_OPTIMIZER_BRANCH="${KRUIZE_OPTIMIZER_BRANCH:-mvp_demo}"
export BENCHMARKS_BRANCH="${BENCHMARKS_BRANCH:-}"

# Pre-process long options before passing to getopts
args=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--autotune-branch)
			export AUTOTUNE_BRANCH="$2"
			shift 2
			;;
		--autotune-branch=*)
			export AUTOTUNE_BRANCH="${1#*=}"
			shift
			;;
		--operator-branch)
			export KRUIZE_OPERATOR_BRANCH="$2"
			shift 2
			;;
		--operator-branch=*)
			export KRUIZE_OPERATOR_BRANCH="${1#*=}"
			shift
			;;
		--optimizer-branch)
			export KRUIZE_OPTIMIZER_BRANCH="$2"
			shift 2
			;;
		--optimizer-branch=*)
			export KRUIZE_OPTIMIZER_BRANCH="${1#*=}"
			shift
			;;
		--benchmarks-branch)
			export BENCHMARKS_BRANCH="$2"
			shift 2
			;;
		--benchmarks-branch=*)
			export BENCHMARKS_BRANCH="${1#*=}"
			shift
			;;
		--branch)
			export AUTOTUNE_BRANCH="$2"
			export KRUIZE_OPERATOR_BRANCH="$2"
			export KRUIZE_OPTIMIZER_BRANCH="$2"
			export BENCHMARKS_BRANCH="$2"
			shift 2
			;;
		--branch=*)
			branch_val="${1#*=}"
			export AUTOTUNE_BRANCH="${branch_val}"
			export KRUIZE_OPERATOR_BRANCH="${branch_val}"
			export KRUIZE_OPTIMIZER_BRANCH="${branch_val}"
			export BENCHMARKS_BRANCH="${branch_val}"
			shift
			;;
		*)
			args+=("$1")
			shift
			;;
	esac
done
set -- "${args[@]}"

# Iterate through the commandline options
while getopts c:kfi:no:pstu: gopts
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

export EXPERIMENTS=("create_tfb-db_exp" "create_tfb_exp" "create_petclinic_semeru_exp")

if [[ "${CLUSTER_TYPE}" == "minikube" ]] || [[ "${CLUSTER_TYPE}" == "kind" ]]; then
	NAMESPACE="monitoring"
else
	NAMESPACE="openshift-tuning"
	export EXPERIMENTS=("create_tfb-db_exp_ocp" "create_tfb_exp_ocp" "create_petclinic_semeru_exp_ocp")
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
else
	echo >> "${LOG_FILE}" 2>&1
	kruize_local_demo_terminate
	echo "For detailed logs, look in kruize-demo.log"
	echo
fi
