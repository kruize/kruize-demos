#!/bin/bash
#
# Copyright (c) 2020, 2022 Red Hat, IBM Corporation and others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
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
unset DRIVER
unset CRUNTIME

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

function err_exit() {
	echo "$*"
	exit 1
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
#   Clone git Repos
###########################################
function clone_repos() {
  app_name=$1
	echo
	echo "#######################################"
	echo "1. Cloning ${app_name} git repos"
	if [ ! -d ${app_name} ]; then
		git clone git@github.com:kruize/${app_name}.git 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kruize/${app_name}.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kruize/${app_name} failed."
	fi

	echo "done"
	echo "#######################################"
	echo
}

###########################################
#   Cleanup git Repos
###########################################
function delete_repos() {
  app_name=$1
	echo "1. Deleting ${app_name} git repos"
	rm -rf ${app_name} benchmarks
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
		echo -n "Waiting 30 seconds for Prometheus to get initialized..."
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
#  Expose Prometheus port
###########################################
function expose_prometheus() {
	kubectl_cmd="kubectl -n monitoring"
	echo "8. Port forwarding Prometheus"
	echo "Info: Prometheus accessible at http://localhost:9090"
	${kubectl_cmd} port-forward prometheus-k8s-1 9090:9090
}

if ! which minikube >/dev/null 2>/dev/null; then
	echo "ERROR: Please install minikube and try again"
	print_min_resources
	exit 1
fi

# check system configs
sys_cpu_mem_check
