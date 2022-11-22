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

# include the common_utils.sh script to access methods
current_dir="$(dirname "$0")"
source ${current_dir}/common_helper.sh

# Default docker image repo
AUTOTUNE_DOCKER_REPO="docker.io/kruize/autotune_operator"

function usage() {
	echo "Usage: $0 [-s|-t] [-d] [-p] [-i autotune-image] [-o hpo-image] [-r]"
	echo "s = start (default), t = terminate"
	echo "r = restart autotune only"
	echo "d = Don't start experiments"
	echo "p = expose prometheus port"
	exit 1
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
		# Checkout the mvp_demo branch for now
		git checkout mvp_demo

		AUTOTUNE_VERSION="$(grep -A 1 "autotune" pom.xml | grep version | awk -F '>' '{ split($2, a, "<"); print a[1] }')"
		YAML_TEMPLATE="./manifests/autotune-operator-deployment.yaml_template"
		YAML_TEMPLATE_OLD="./manifests/autotune-operator-deployment.yaml_template.old"

		./deploy.sh -c minikube -t 2>/dev/null
		sleep 5
		if [ -z "${AUTOTUNE_DOCKER_IMAGE}" ]; then
			AUTOTUNE_DOCKER_IMAGE=${AUTOTUNE_DOCKER_REPO}:${AUTOTUNE_VERSION}
		fi
		DOCKER_IMAGES="-i ${AUTOTUNE_DOCKER_IMAGE}"
		if [ ! -z "${HPO_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -o ${HPO_DOCKER_IMAGE}"
		fi
		echo
		echo "Starting install with  ./deploy.sh -c minikube ${DOCKER_IMAGES}"
		echo

		if [ ${EXPERIMENT_START} -eq 0 ]; then
			cp ${YAML_TEMPLATE} ${YAML_TEMPLATE_OLD}
			sed -e "s/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g" ${YAML_TEMPLATE_OLD} > ${YAML_TEMPLATE}
			CURR_DRIVER=$(minikube config get driver 2>/dev/null)
			if [ "${CURR_DRIVER}" == "docker" ]; then
				echo "Setting docker env"
				eval $(minikube docker-env)
			elif [ "${CURR_DRIVER}" == "podman" ]; then
				echo "Setting podman env"
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
	echo "Info: Autotune Trials Status at http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/listTrialStatus?experiment_name=quarkus-resteasy-autotune-min-http-response-time-db&trial_number=0&verbose=true"
	echo "Info: List Layers in autotune http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/query/listStackLayers?deployment_name=autotune&namespace=monitoring"
	echo "Info: List Layers in tfb http://${MINIKUBE_IP}:${AUTOTUNE_PORT}/query/listStackLayers?deployment_name=tfb-qrh-sample&namespace=default"

	echo
	echo "Info: Access autotune objects using: kubectl -n default get autotune"
	echo "Info: Access autotune tunables using: kubectl -n monitoring get autotuneconfig"
	echo "#######################################"
	echo
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
		clone_repos autotune
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
	delete_repos autotune
	minikube_delete
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Autotune demo cleanup took ${elapsed_time} seconds"
	echo
}

# By default we start the demo and dont expose prometheus port
prometheus=0
autotune_restart=0
start_demo=1
DOCKER_IMAGES=""
AUTOTUNE_DOCKER_IMAGE=""
HPO_DOCKER_IMAGE=""
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
			HPO_DOCKER_IMAGE="${OPTARG}"
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
