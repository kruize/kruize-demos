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
common_dir="${current_dir}/../../../common/"
source ${common_dir}/common_helper.sh
source ${current_dir}/../common.sh

# Default docker image repo
export KRUIZE_DOCKER_REPO="quay.io/kruize/autotune_operator"

# Default cluster
export CLUSTER_TYPE="minikube"

# Target mode, default "crc"; "autotune" is currently broken
export target="crc"

KIND_IP=127.0.0.1
KRUIZE_PORT=8080
THANOS_PORT=9090
MINIO_PORT=9000
KRUIZE_UI_PORT=8081
TECHEMPOWER_PORT=8082

PYTHON_CMD=python3
export LOG_FILE="${current_dir}/kruize-bulk-demo.log"

function usage() {
	echo "Usage: $0 [-s|-t] [-c cluster-type] [-l] [-p] [-f] [-i kruize-image] [-u kruize-ui-image]"
	echo "[-z] [-q thanos datasource url. Default - http://${KIND_IP}:${THANOS_PORT}]"
	echo "c = supports minikube, kind and openshift cluster-type"
	echo "i = kruize image. Default - quay.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "p = expose prometheus port"
	echo "l = to deploy TFB with load"
	echo "f = enable environment setup"
	echo "s = start (default), t = terminate"
	echo "z = register thanos datasource with Kruize (supported only with openshift/kind cluster type)"
	echo "q = thanos datasource url. Default - http://${KIND_IP}:${THANOS_PORT}]"
	echo "u = Kruize UI Image. Default - quay.io/kruize/kruize-ui:<version as in package.json>"
	echo "n = namespace of benchmark. Default - default"
	echo "d = duration to run the benchmark load"

	exit 1
}

function kruize_bulk() {
  echo "Running bulk_demo.py..." >> "${LOG_FILE}" 2>&1
  "${PYTHON_CMD}" -u bulk_demo.py -c "${CLUSTER_TYPE}" -z "${thanos}"
  {
  echo
  echo "######################################################"
  echo
  } >> "${LOG_FILE}" 2>&1
}

# Check system configs
sys_cpu_mem_check

# By default we start the demo and dont expose prometheus port
export DOCKER_IMAGES=""
export KRUIZE_DOCKER_IMAGE=""
export prometheus=0
export env_setup=0
export start_demo=1
export thanos=0
export ds_url="http://thanos-query-frontend-example-query.thanos-operator-system.svc:9090"
export minio_url="http://${KIND_IP}:${MINIO_PORT}"
export APP_NAMESPACE="default"
export LOAD_DURATION="1200"

# Iterate through the commandline options
while getopts c:i:n:d:q:lpfstzu: gopts
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
		f)
			env_setup=1
			;;
	  	l)
			start_demo=2
			;;
		s)
			start_demo=1
			;;
		z)
			thanos=1
			;;
		t)
			start_demo=0
			;;
		q)
			ds_url="${OPTARG}"
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
if [[ "${CLUSTER_TYPE}" == "minikube" && "${thanos}" == "1" ]]; then
	echo "Thanos Demo is not supported on minikube cluster"
	usage
	exit 1
fi

if [ ${start_demo} -eq 1 ]; then
	echo > "${LOG_FILE}" 2>&1
	kruize_local_demo_setup
	echo "For detailed logs, look in kruize-bulk-demo.log"
	echo
elif [ ${start_demo} -eq 2 ]; then
	kruize_local_demo_update
else
	echo >> "${LOG_FILE}" 2>&1
	kruize_local_demo_terminate
	echo "For detailed logs, look in kruize-bulk-demo.log"
	echo
fi
