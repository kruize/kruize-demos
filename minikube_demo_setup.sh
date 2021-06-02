#!/bin/bash
#
# Copyright (c) 2020, 2021 Red Hat, IBM Corporation and others.
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

function usage() {
	echo "Usage: $0 [-s|-t] [-p]"
	echo "s = start (default), t = terminate"
	echo "r = restart autotune only"
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
		exit -1
	fi
}

###########################################
#   Clone Autotune git Repos
###########################################
function clone_repos() {
	echo
	echo "#######################################"
	echo "1. Cloning autotune git repos"
	git clone git@github.com:kruize/autotune.git 2>/dev/null
	check_err "ERROR: git clone git@github.com:kruize/autotune.git failed."
	pushd autotune >/dev/null
		git checkout master
		git pull
	popd >/dev/null
	git clone git@github.com:kruize/benchmarks.git 2>/dev/null
	check_err "ERROR: git clone git@github.com:kruize/benchmarks.git failed."
	pushd benchmarks >/dev/null
		git checkout master
		git pull
	popd >/dev/null
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
	echo
	echo "#######################################"
	echo "2. Deleting minikube cluster, if any"
	minikube delete
	sleep 2
	echo "3. Starting new minikube cluster"
	echo
	minikube start
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
		echo "5. Installing galaxies (quarkus REST CRUD) benchmark into cluster"
		pushd galaxies >/dev/null
			kubectl apply -f manifests
			check_err "ERROR: Galaxies app failed to start, exiting"
		popd >/dev/null

		echo "6. Installing petclinic (springboot REST CRUD) benchmark into cluster"
		pushd spring-petclinic >/dev/null
			kubectl apply -f manifests
			check_err "ERROR: Petclinic app failed to start, exiting"
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
	echo "7. Installing Autotune"
	pushd autotune >/dev/null
		./deploy.sh -c minikube -t 2>/dev/null
		sleep 5
		if [ -z "${AUTOTUNE_DOCKER_IMAGE}" ]; then
			./deploy.sh -c minikube -i "${AUTOTUNE_DOCKER_IMAGE}"
		else
			./deploy.sh -c minikube
		fi
		check_err "ERROR: Autotune failed to start, exiting"
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
		echo "8. Installing Autotune Object for galaxies app"
		pushd galaxies >/dev/null
			kubectl apply -f autotune/autotune-http_resp_time.yaml
			check_err "ERROR: Failed to create Autotune object for galaxies, exiting"
		popd >/dev/null

		echo "9. Installing Autotune Object for petclinic app"
		pushd spring-petclinic >/dev/null
			kubectl apply -f autotune/autotune-http_throughput.yaml
			check_err "ERROR: Failed to create Autotune object for petclinic, exiting"
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
	GALAXIES_PORT=$(${kubectl_cmd} get svc galaxies-service --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
	PETCLINIC_PORT=$(${kubectl_cmd} get svc petclinic-service --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
	MINIKUBE_IP=$(minikube ip)

	echo
	echo "#######################################"
	echo "#             Quarkus App             #"
	echo "#######################################"
	echo "Info: Access galaxies app at http://${MINIKUBE_IP}:${GALAXIES_PORT}"
	echo "Info: Access galaxies app metrics at http://${MINIKUBE_IP}:${GALAXIES_PORT}/metrics"
	echo
	echo "#######################################"
	echo "#           Springboot App            #"
	echo "#######################################"
	echo "Info: Access petclinic app at http://${MINIKUBE_IP}:${PETCLINIC_PORT}"
	echo "Info: Access petclinic app metrics at http://${MINIKUBE_IP}:${PETCLINIC_PORT}/manage/prometheus"
	echo
	echo "#######################################"
	echo "#              Autotune               #"
	echo "#######################################"
	echo "Info: Access Autotune tunables at http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listAutotuneTunables"
	echo "Info: Autotune is monitoring these apps http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listApplications"
	echo "Info: List Layers in apps that Autotune is monitoring http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listAppLayers"
	echo "Info: List Tunables in apps that Autotune is monitoring http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listAppTunables"
	echo "Info: Autotune searchSpace at http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/searchSpace"
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
	echo "10. Port forwarding Prometheus"
	echo "Info: Prometheus accessible at http://localhost:9090"
	${kubectl_cmd} port-forward prometheus-k8s-1 9090:9090
}

function autotune_start() {
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
	autotune_objects_install
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
	echo "       Minikube resources needed for demo"
	echo "       CPUs=8, Memory=16384MB"
	exit 1
fi

# By default we start the demo and dont expose prometheus port
prometheus=0
autotune_restart=0
start_demo=1
AUTOTUNE_DOCKER_IMAGE=""
# Iterate through the commandline options
while getopts i:prst gopts
do
	case "${gopts}" in
		i)
			AUTOTUNE_DOCKER_IMAGE="${OPTARG}"
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
