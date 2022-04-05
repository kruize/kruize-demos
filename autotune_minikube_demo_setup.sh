#!/bin/bash
#
# Copyright (c) 2020, 2022 Red Hat, IBM Corporation and others.
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

# Minimum resources required to run the demo
MIN_CPU=8
MIN_MEM=16384

# Change both of these to docker if you are using docker
DRIVER="podman"
CRUNTIME="cri-o"
# Comment this for development
unset ${DRIVER}
unset ${CRUNTIME}

# Default docker image repos
AUTOTUNE_DOCKER_REPO="docker.io/kruize/autotune_operator"
OPTUNA_DOCKER_REPO="docker.io/kruize/autotune_optuna"

function usage() {
	echo "Usage: $0 [-s|-t] [-d] [-p] [-i autotune-image] [-o optuna-image] [-r]"
	echo "s = start (default), t = terminate"
	echo "r = restart autotune only"
	echo "d = Don't start experiments"
	echo "p = expose prometheus port"
	exit 1
}

# get date in format
function get_date() {
	date "+%Y-%m-%d %H:%M:%S"
}

function time_diff() {
	ssec=`date --utc --date "$1" +%s`
	esec=`date --utc --date "$2" +%s`

	diffsec=$(($esec-$ssec))
	echo $diffsec
}

function check_err() {
	err=$?
	if [ ${err} -ne 0 ]; then
		echo "$*"
		exit 1
	fi
}

# Prints the minimum system resources required to run the demo
function print_min_resources() {
	echo "       Minikube resource config needed for demo:"
	echo "       CPUs=8, Memory=16384MB"
}

# Checks if the system which tries to run autotune is having minimum resources required
function sys_cpu_mem_check() {
	SYS_CPU=$(cat /proc/cpuinfo | grep "^processor" | wc -l)
	SYS_MEM=$(grep MemTotal /proc/meminfo | awk '{printf ("%.0f\n", $2/(1024))}')

	if [ "${SYS_CPU}" -lt "${MIN_CPU}" ]; then
		echo "CPU's on system : ${SYS_CPU} | Minimum CPU's required for demo : ${MIN_CPU}"
		print_min_resources
		echo "ERROR: Exiting due to lack of system resources."
		exit 1
	fi

	if [ "${SYS_MEM}" -lt "${MIN_MEM}" ]; then
		echo "Memory on system : ${SYS_MEM} | Minimum Memory required for demo : ${MIN_MEM}"
		print_min_resources
		echo "ERROR: Exiting due to lack of system resources."
		exit 1
	fi
}

###########################################
#   Clone Autotune git Repos
###########################################
function clone_repos() {
	echo
	echo "#######################################"
	echo "1. Cloning autotune git repos"
	if [ ! -d autotune ]; then
		git clone git@github.com:kruize/autotune.git 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kruize/autotune.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kruize/autotune failed."
	fi

	if [ ! -d benchmarks ]; then
		git clone git@github.com:kruize/benchmarks.git 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kruize/benchmarks.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kruize/benchmarks failed."
	fi
	echo "done"
	echo "#######################################"
	echo
}

###########################################
#   Cleanup Autotune git Repos
###########################################
function delete_repos() {
	echo "1. Deleting autotune git repos"
	rm -rf autotune benchmarks
}

###########################################
#   Minikube Start
###########################################
function minikube_start() {
	minikube config set cpus ${MIN_CPU} >/dev/null 2>/dev/null
	minikube config set memory ${MIN_MEM}M >/dev/null 2>/dev/null
	if [ -n "${DRIVER}" ]; then
		minikube config set driver ${DRIVER} >/dev/null 2>/dev/null
		minikube config set container-runtime ${CRUNTIME} >/dev/null 2>/dev/null
	fi
	echo
	echo "#######################################"
	echo "2. Deleting minikube cluster, if any"
	minikube delete
	sleep 2
	echo "3. Starting new minikube cluster"
	echo
	if [ -n "${DRIVER}" ]; then
		minikube start --cpus=${MIN_CPU} --memory=${MIN_MEM}M --driver=${DRIVER} --container-runtime=${CRUNTIME}
	else
		minikube start --cpus=${MIN_CPU} --memory=${MIN_MEM}M
	fi
	check_err "ERROR: minikube failed to start, exiting"
	echo -n "Waiting for cluster to be up..."
	sleep 10
	echo "done"
	echo "#######################################"
	echo
}

###########################################
#   Minikube Delete
###########################################
function minikube_delete() {
	echo "2. Deleting minikube cluster"
	minikube delete
	sleep 2
	echo
}

###########################################
#   Prometheus and Grafana Install
###########################################
function prometheus_install() {
	echo
	echo "#######################################"
	echo "4. Installing Prometheus and Grafana"
	pushd autotune >/dev/null
		./scripts/prometheus_on_minikube.sh -as
		check_err "ERROR: Prometheus failed to start, exiting"
		echo -n "Waiting 30 seconds for Prometheus to get initiliazed..."
		sleep 30
		echo "done"
	popd >/dev/null
	echo "#######################################"
	echo
}

###########################################
#   Benchmarks Install
###########################################
function benchmarks_install() {
	echo
	echo "#######################################"
	pushd benchmarks >/dev/null
		echo "5. Installing TechEmpower (Quarkus REST EASY) benchmark into cluster"
		pushd techempower >/dev/null
			kubectl apply -f manifests
			check_err "ERROR: TechEmpower app failed to start, exiting"
		popd >/dev/null
	popd >/dev/null
	echo "#######################################"
	echo
}

###########################################
#   Autotune Install
###########################################
function autotune_install() {
	echo
	echo "#######################################"
	echo "6. Installing Autotune"
	if [ ! -d autotune ]; then
		echo "ERROR: autotune dir not found."
		if [ ${autotune_restart} -eq 1 ]; then
			echo "ERROR: autotune not running. Wrong use of restart command"
		fi
		exit -1
	fi
	pushd autotune >/dev/null
		AUTOTUNE_VERSION="$(grep -A 1 "autotune" pom.xml | grep version | awk -F '>' '{ split($2, a, "<"); print a[1] }')"
		YAML_TEMPLATE="./manifests/autotune-operator-deployment.yaml_template"
		YAML_TEMPLATE_OLD="./manifests/autotune-operator-deployment.yaml_template.old"

		./deploy.sh -c minikube -t 2>/dev/null
		sleep 5
		if [ -z "${AUTOTUNE_DOCKER_IMAGE}" ]; then
			AUTOTUNE_DOCKER_IMAGE=${AUTOTUNE_DOCKER_REPO}:${AUTOTUNE_VERSION}
		fi
		if [ -z "${OPTUNA_DOCKER_IMAGE}" ]; then
			OPTUNA_DOCKER_IMAGE=${OPTUNA_DOCKER_REPO}:${AUTOTUNE_VERSION}
		fi
		DOCKER_IMAGES="-i ${AUTOTUNE_DOCKER_IMAGE} -o ${OPTUNA_DOCKER_IMAGE}"
		echo
		echo "Starting install with  ./deploy.sh -c minikube ${DOCKER_IMAGES}"
		echo

		if [ ${EXPERIMENT_START} -eq 0 ]; then
			cp ${YAML_TEMPLATE} ${YAML_TEMPLATE_OLD}
			sed -e "s/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g" ${YAML_TEMPLATE_OLD} > ${YAML_TEMPLATE}
			CURR_DRIVER=$(minikube config get driver 2>/dev/null)
			if [ "${CURR_DRIVER}" == "docker" ]; then
				eval $(minikube docker-env)
			elif [ "${CURR_DRIVER}" == "podman" ]; then
				eval $(minikube podman-env)
			fi
		fi

		./deploy.sh -c minikube ${DOCKER_IMAGES}
		check_err "ERROR: Autotune failed to start, exiting"

		if [ ${EXPERIMENT_START} -eq 0 ]; then
			cp ${YAML_TEMPLATE_OLD} ${YAML_TEMPLATE} 2>/dev/null
		fi
		echo -n "Waiting 30 seconds for Autotune to sync with Prometheus..."
		sleep 30
		echo "done"
	popd >/dev/null
	echo "#######################################"
	echo
}

###########################################
#   Install Autotune Objects
###########################################
function autotune_objects_install() {
	echo
	echo "#######################################"
	pushd benchmarks >/dev/null
		echo "7. Installing Autotune Object for techempower app"
		pushd techempower >/dev/null
			kubectl apply -f autotune/autotune-http_resp_time.yaml
			check_err "ERROR: Failed to create Autotune object for techempower, exiting"
		popd >/dev/null
	popd >/dev/null
	echo "#######################################"
	echo
}

###########################################
#  Get URLs
###########################################
function get_urls() {

	kubectl_cmd="kubectl -n monitoring"
	AUTOTUNE_PORT=$(${kubectl_cmd} get svc autotune --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)

	kubectl_cmd="kubectl -n default"
	TECHEMPOWER_PORT=$(${kubectl_cmd} get svc tfb-qrh-service --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
	MINIKUBE_IP=$(minikube ip)

	echo
	echo "#######################################"
	echo "#             Quarkus App             #"
	echo "#######################################"
	echo "Info: Access techempower app at http://${MINIKUBE_IP}:${TECHEMPOWER_PORT}/db"
        echo "Info: Access techempower app metrics at http://${MINIKUBE_IP}:${TECHEMPOWER_PORT}/q/metrics"
	echo
	echo "#######################################"
	echo "#              Autotune               #"
	echo "#######################################"
	echo "Info: Access Autotune tunables at http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listAutotuneTunables"
	echo "######  The following links are meaningful only after an autotune object is deployed ######"
	echo "Info: Autotune is monitoring these apps http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listStacks"
	echo "Info: List Layers in apps that Autotune is monitoring http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listStackLayers"
	echo "Info: List Tunables in apps that Autotune is monitoring http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listStackTunables"
	echo "Info: Autotune searchSpace at http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/searchSpace"
	echo "Info: Autotune Experiments at http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listExperiments"
	echo "Info: Autotune Experiments Summary at http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/experimentsSummary"
	echo "Info: Autotune Trials Status at http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listTrialStatus"

	echo
	echo "Info: Access autotune objects using: kubectl -n default get autotune"
	echo "Info: Access autotune tunables using: kubectl -n monitoring get autotuneconfig"
	echo "#######################################"
	echo
}

###########################################
#  Expose Prometheus port
###########################################
function expose_prometheus() {
	kubectl_cmd="kubectl -n monitoring"
	echo "8. Port forwarding Prometheus"
	echo "Info: Prometheus accessible at http://localhost:9090"
	${kubectl_cmd} port-forward prometheus-k8s-1 9090:9090
}

function autotune_start() {
	minikube >/dev/null
	check_err "ERROR: minikube not installed"
	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#        Autotune Demo Setup          #"
	echo "#######################################"
	echo

	if [ ${autotune_restart} -eq 0 ]; then
		clone_repos
		minikube_start
		prometheus_install
		benchmarks_install
	fi
	autotune_install
	if [ ${EXPERIMENT_START} -eq 1 ]; then
		autotune_objects_install
	fi
	echo
	kubectl -n monitoring get pods
	echo
	get_urls
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Autotune demo setup took ${elapsed_time} seconds"
	echo
	if [ ${prometheus} -eq 1 ]; then
		expose_prometheus
	fi
}

function autotune_terminate() {
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#       Autotune Demo Terminate       #"
	echo "#######################################"
	echo
	delete_repos
	minikube_delete
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Autotune demo cleanup took ${elapsed_time} seconds"
	echo
}

if ! which minikube >/dev/null 2>/dev/null; then
	echo "ERROR: Please install minikube and try again"
	print_min_resources
	exit 1
fi

sys_cpu_mem_check

# By default we start the demo and dont expose prometheus port
prometheus=0
autotune_restart=0
start_demo=1
DOCKER_IMAGES=""
AUTOTUNE_DOCKER_IMAGE=""
OPTUNA_DOCKER_IMAGE=""
EXPERIMENT_START=1
# Iterate through the commandline options
while getopts di:o:prst gopts
do
	case "${gopts}" in
		d)
			EXPERIMENT_START=0
			;;
		i)
			AUTOTUNE_DOCKER_IMAGE="${OPTARG}"
			;;
		o)
			OPTUNA_DOCKER_IMAGE="${OPTARG}"
			;;
		p)
			prometheus=1
			;;
		r)
			autotune_restart=1
			;;
		s)
			start_demo=1
			;;
		t)
			start_demo=0
			;;
		*)
			usage
	esac
done

if [ ${start_demo} -eq 1 ]; then
	autotune_start
else
	autotune_terminate
fi
