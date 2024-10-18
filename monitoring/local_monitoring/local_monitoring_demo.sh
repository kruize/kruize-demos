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
source ${current_dir}/common.sh

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

function usage() {
	echo "Usage: $0 [-s|-t] [-c cluster-type] [-e recommendation_experiment] [-l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image] [-b] [-n namespace] [-d load-duration] [-m benchmark-manifests]"
	echo "c = supports minikube, kind, aks and openshift cluster-type"
	echo "e = supports container, namespace and gpu"
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
	echo "g = number of unpartitioned gpus in cluster"

	exit 1
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
export GPUS="0"
export EXPERIMENT_TYPE=""
# Iterate through the commandline options
while getopts c:i:e:n:d:m:g:lbprstu: gopts
do
	case "${gopts}" in
		c)
			CLUSTER_TYPE="${OPTARG}"
			;;
		i)
			KRUIZE_DOCKER_IMAGE="${OPTARG}"
			;;
		e)
			EXPERIMENT_TYPE="${OPTARG}"
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
		g)
			GPUS="${OPTARG}"
			;;
		*)
			usage
	esac
done

export demo="local"
#EXPERIMENTS=("create_human_eval_exp" "create_llm_rag_exp" "create_namespace_exp" "create_tfb-db_exp" "create_tfb_exp" "create_ttm_exp")

if [ "${EXPERIMENT_TYPE}" == "container" ]; then
	export EXPERIMENTS=("create_tfb-db_exp" "create_tfb_exp")
	BENCHMARK="tfb"
elif [ "${EXPERIMENT_TYPE}" == "namespace" ]; then
        export EXPERIMENTS=("create_namespace_exp")
	BENCHMARK="tfb"
elif [ "${EXPERIMENT_TYPE}" == "gpu" ]; then
	export EXPERIMENTS=("create_human_eval_exp")
	BENCHMARK="human-eval"
	gpu_nodes=$(oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | grep -v '<none>' | awk '$2 > 0')
	if [ -z "$gpu_nodes" ]; then
	    	echo "No GPU resources found in the cluster. Exiting!"
	    	exit 0
	fi
else
	export EXPERIMENTS=()
fi

echo | tee "${LOG_FILE}"
if [ ${start_demo} -eq 1 ]; then
	kruize_local_demo_setup ${BENCHMARK}
	echo "For installation logs, look in kruize-demo.log" | tee -a "${LOG_FILE}"
elif [ ${start_demo} -eq 2 ]; then
	echo "Updating the kruize local demo..." | tee -a "${LOG_FILE}"
	kruize_local_demo_update ${BENCHMARK} >> "${LOG_FILE}" 2>&1
else
	echo "Terminating kruize local demo..." | tee -a "${LOG_FILE}"
	kruize_local_demo_terminate >> "${LOG_FILE}" 2>&1
fi
