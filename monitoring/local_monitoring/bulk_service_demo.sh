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

KIND_IP=127.0.0.1
KRUIZE_PORT=8080
KRUIZE_UI_PORT=8081
TECHEMPOWER_PORT=8082

PYTHON_CMD=python3

function usage() {
	echo "Usage: $0 [-s|-t] [-c cluster-type] [l] [-p] [-r] [-i kruize-image] [-u kruize-ui-image]"
	echo "c = supports minikube, kind and openshift cluster-type"
	echo "i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "p = expose prometheus port"
	echo "r = restart kruize only"
	echo "s = start (default), t = terminate"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "n = namespace of benchmark. Default - default"
	echo "d = duration to run the benchmark load"

	exit 1
}

function kruize_bulk() {
  echo "Running bulk_demo.py..."
  "${PYTHON_CMD}" bulk_demo.py -c "${CLUSTER_TYPE}"

  echo
  echo "Bulk API Job status is captured in job_status.json"
  echo
  echo "Recommendations for all experiments are available in recommendations_data.json"
  echo
  echo "List Recommendations using "
  echo "curl http://${KRUIZE_URL}/listRecommendations?experiment_name='prometheus-1|default|tfb-1|tfb-qrh-sample(deployment)|tfb-server'"
  echo "curl http://${KRUIZE_URL}/listRecommendations?experiment_name='prometheus-1|default|tfb-2|tfb-qrh-sample(deployment)|tfb-server'"
  echo "curl http://${KRUIZE_URL}/listRecommendations?experiment_name='prometheus-1|default|tfb-3|tfb-qrh-sample(deployment)|tfb-server'"
  echo
  echo "######################################################"
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

export demo="bulk"
if [ ${start_demo} -eq 1 ]; then
	kruize_local_demo_setup 
else
	kruize_local_demo_terminate
fi
