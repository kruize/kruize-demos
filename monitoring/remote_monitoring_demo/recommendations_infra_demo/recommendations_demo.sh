#!/bin/bash
#
# Copyright (c) 2023, 2023 Red Hat, IBM Corporation and others.
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

current_dir="$(dirname "$0")"
source ${current_dir}/../../../common/common_helper.sh
source ${current_dir}/recommendations_demo/recommendation_helper.sh
# Default docker image repos
AUTOTUNE_DOCKER_REPO="docker.io/kruize/autotune_operator"

echo "${current_dir}/recommendations_demo/recommendation_helper.sh"

# Default cluster
CLUSTER_TYPE="openshift"

target="crc"
visualize=0

function usage() {
	echo "Usage: $0 [-s|-t] [-o kruize-image] [-r] [-a] [-c cluster-type] [-d] [--summarize] [--visualize]"
	echo "s = start (default), t = terminate"
	echo "r = restart kruize monitoring only"
	echo "a = feed experiments to existing kruize deployment"
	echo "g = get the metrics and recommendations of all experiments in kruize in csv format"
	echo "o = kruize image. Default - docker.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "c = supports minikube and openshift cluster-type"
	echo "d = duration of benchmark warmup/measurement cycles"
	echo "p = expose prometheus port"
	echo "summarizeClusters = Summarize the cluster data. Default - all clusters. Append --clusterName=<> and --namespaceName=<> for individual summary"
	echo "summarizeNamespaces = Summarize the namespace data. Default - all namespaces. Append --namespaceName=<> for individual summary"
	echo "validate = Validates the recommendations for a set of experiments"
	echo "visualize = Visualize the recommendations in grafana (Yet to be implemented)"
	exit 1
}

## Checks for the pre-requisites to run the monitoring demo
function prereq_check() {
	# Python is required only to run the monitoring experiment 
	python3 --version >/dev/null 2>/dev/null
	check_err "ERROR: python3 not installed. Required to start the demo. Check if all dependencies (python3,minikube) are installed."

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube >/dev/null 2>/dev/null
		check_err "ERROR: minikube not installed."
		kubectl get pods >/dev/null 2>/dev/null
		check_err "ERROR: minikube not running. "
		## Check if prometheus is running for valid benchmark results.
		#prometheus_pod_running=$(kubectl get pods --all-namespaces | grep "prometheus-k8s-0")
		#if [ "${prometheus_pod_running}" == "" ]; then
		#	err_exit "Install prometheus for valid results from benchmark."
		#fi
	fi
}

###########################################
#   Kruize Install
###########################################
function kruize_install() {
	echo
	echo "#######################################"
	echo " Installing Kruize"
	if [ ! -d autotune ]; then
		echo "ERROR: autotune dir not found."
		if [ ${autotune_restart} -eq 1 ]; then
			echo "ERROR: Kruize not running. Wrong use of restart command"
		fi
		exit -1
	fi
	pushd autotune >/dev/null
		# Checkout the mvp_demo branch for now
		git checkout mvp_demo
		kruize_local_disable
		kruize_remote_demo_patch

		AUTOTUNE_VERSION="$(grep -A 1 "autotune" pom.xml | grep version | awk -F '>' '{ split($2, a, "<"); print a[1] }')"

		echo "Terminating existing installation of kruize with  ./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t"
		./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t
		sleep 5
		if [ -z "${AUTOTUNE_DOCKER_IMAGE}" ]; then
			AUTOTUNE_DOCKER_IMAGE=${AUTOTUNE_DOCKER_REPO}:${AUTOTUNE_VERSION}
		fi
		DOCKER_IMAGES="-i ${AUTOTUNE_DOCKER_IMAGE}"
		if [ ! -z "${HPO_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -o ${AUTOTUNE_DOCKER_IMAGE}"
		fi
		echo
		echo "Starting kruize installation with  ./deploy.sh -c ${CLUSTER_TYPE} ${DOCKER_IMAGES} -m ${target}"
		echo

		./deploy.sh -c ${CLUSTER_TYPE} ${DOCKER_IMAGES} -m ${target}
		#./deploy.sh -c minikube -i docker.io/kruize/autotune_operator:0.0.13_mvp -m crc
		check_err "ERROR: kruize failed to start, exiting"

		echo -n "Waiting 40 seconds for Autotune to sync with Prometheus..."
		sleep 40
		echo "done"
	popd >/dev/null
	echo "#######################################"
	echo
}

function monitoring_demo_setup() {

        #minikube >/dev/null
        #check_err "ERROR: minikube not installed"
        # Start all the installs
        echo
        echo "#######################################"
        echo "#           Demo Setup                #"
        echo "#######################################"
        echo
        echo "--> Clone Required Repos"

        if [ ${CLUSTER_TYPE} == "minikube" ]; then
                echo "--> Setup minikube"
                echo "--> Installs Prometheus"
        fi

        echo "--> Installs Kruize"
        echo "--> Creates experiments in monitoring mode"
        echo "--> Updates the results into Kruize"
        echo "--> Fetches the recommendations from Kruize"
        echo

        if [ ${cluster_monitoring_setup} -eq 1 ]; then
                if [ ${CLUSTER_TYPE} == "minikube" ]; then
                        echo "Starting minikube"
                        minikube_start

			CURR_DRIVER=$(minikube config get driver 2>/dev/null)
                        if [ "${CURR_DRIVER}" == "docker" ]; then
                                echo "Setting docker env"
 				eval $(minikube docker-env)
                        elif [ "${CURR_DRIVER}" == "podman" ]; then
                                echo "Setting podman env"
 				eval $(minikube podman-env)
                        fi
                fi
		if [[ ${monitorRecommendations} == 1 ]]; then
			## Check if prometheus is running for valid benchmark results.
			prometheus_pod_running=$(kubectl get pods --all-namespaces | grep "prometheus-k8s-0")
			if [ "${prometheus_pod_running}" == "" ]; then
				echo "Calling prometheus_install"
				prometheus_install
				echo "Calling prometheus_install done"
			fi
		fi
	fi

        # Check for pre-requisites to run the demo
        python3 -m pip install --user -r requirements.txt >/dev/null 2>&1
        prereq_check ${CLUSTER_TYPE}

        kruize_install

}

function monitoring_demo_start() {

	start_time=$(get_date)

	if [[ ${demo_monitoring_setup} -eq 1 ]]; then
		clone_repos autotune
		monitoring_demo_setup
	fi

	# Deploy benchmarks. Create an experiment, update results and fetch recommendations using Kruize REST APIs
	if [[ ${dataDrivenRecommendations} -eq 1 ]]; then
		echo "#######################################"
		# crc mode considers the individual data. Else, it considers the aggregated data.
		if [[ ${mode} == "crc" ]]; then
			echo "Running the recommendation Infra demo with the existing data in crc mode..."
			monitoring_recommendations_demo_with_data ${resultsDir} crc false ${bulkResults} ${daysData}
		else
			echo "Running the recommendation Infra demo with the existing data..."
			monitoring_recommendations_demo_with_data ${resultsDir} "" false ${bulkResults} ${daysData}
		fi
		echo
		echo "Completed"
		echo "#######################################"
		echo ""
		echo "Use experimentOutput.csv to generate visualizations"
	elif [[ ${monitorRecommendations} -eq 1 ]]; then
		#if [ -z $k8ObjectType ] && [ -z $k8ObjectName ]; then
		if [[ ${demoBenchmark} -eq 1 ]]; then
			echo "Running the monitoring mode  with demo benchmark"
			clone_repos benchmarks
                        monitoring_recommendations_demo_with_benchmark
		else
			echo "Running the monitoring mode on a cluster"
			monitoring_recommendations_demo_for_k8object
		fi
	elif [[ ${compareRecommendations} -eq 1 ]]; then
                comparing_recommendations_demo_with_data ./recommendations_demo/tfb-results/splitfiles
	elif [[ ${setRecommendations} -eq 1 ]]; then
		# Hardcoding to set the recommendations of duration based medium term for every 6 hrs
		timeout 2592000 bash -c "set_recommendations medium_term 21600" &
	elif [[ ${summarizeClusters} -eq 1 ]]; then
		echo "CLUSTER_NAME is ${CLUSTER_NAME}"
		if [[ ! -z ${CLUSTER_NAME} ]]; then
			if [[ ! -z ${NAMESPACE_NAME} ]]; then
				echo "Summarizing cluster:${CLUSTER_NAME} namespace:${NAMESPACE_NAME} data available in kruize"
				summarize_cluster_data ${CLUSTER_NAME} ${NAMESPACE_NAME}
			else
				echo "Summarizing cluster:${CLUSTER_NAME} data available in kruize"
                                summarize_cluster_data ${CLUSTER_NAME}
			fi
		else
			echo "Summarizing all the cluster data available in kruize"
			summarize_cluster_data
		fi
	elif [[ ${summarizeNamespaces} -eq 1 ]]; then
		if [[ ! -z ${NAMESPACE_NAME} ]]; then
			echo "Summarizing namespace:${NAMESPACE_NAME} data available in kruize"
			summarize_namespace_data ${NAMESPACE_NAME}
                else
                        echo "Summarizing all the namespaces data available in kruize"
                        summarize_namespace_data
                        #summarize_all_data
                fi
	elif [[ ${summarizeAll} -eq 1 ]]; then
		echo "Summarizing all the data available in kruize"
		summarize_all_data
	elif [[ ${validateRecommendations} -eq 1 ]]; then
		if [[ -z ${daysData} ]]; then
			echo "Validating the container Recommendations..."
			resultsDir="./recommendations_demo/validateResults"
			monitoring_recommendations_demo_with_data ${resultsDir} crc true ${bulkResults} "" "container"
			echo "-----------------------------------------"
			echo "Validating the namespace Recommendations..."
			resultsDir="./recommendations_demo/validateNamespaceResults"
			monitoring_recommendations_demo_with_data ${resultsDir} "none" true ${bulkResults} "" "namespace"
		else
			echo "Validating the container Recommendations..."
			resultsDir="./recommendations_demo/validateResults"
			monitoring_recommendations_demo_with_data ${resultsDir} crc true ${bulkResults} ${daysData} "container"
			echo "-----------------------------------------"
			echo "Validating the namespace Recommendations..."
			resultsDir="./recommendations_demo/validateNamespaceResults"
			monitoring_recommendations_demo_with_data ${resultsDir} "none" true ${bulkResults} ${daysData} "namespace"
		fi
		validate_experiment_recommendations true
		exit_code=$?
		if [[ ${exit_code} == 0 ]]; then
			exit 0
		else
			exit 1
		fi
	elif [[ ${getMetricsRecommendations} -eq 1 ]]; then
 		echo "Generating the metrics and recommendations for all experiments available in kruize"
 		get_metrics_recommendations
		get_metrics_boxplots
	fi

	echo
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Recommendations Infra demo set-up took ${elapsed_time} seconds"
	echo
	if [ ${prometheus} -eq 1 ]; then
		expose_prometheus
	fi
	
}

function monitoring_demo_terminate() {
	echo
	echo "#######################################"
	echo "#     Monitoring Demo Terminate       #"
	echo "#######################################"
	echo
	pushd autotune >/dev/null
		./deploy.sh -t -c ${CLUSTER_TYPE}
		echo "ERROR: Failed to terminate kruize monitoring"
		echo
	popd >/dev/null
}


function monitoring_demo_cleanup() {
	echo
	echo "#######################################"
	echo "#    Monitoring Demo setup cleanup    #"
	echo "#######################################"
	echo

	delete_repos autotune

	if [ ${visualize} -eq 1 ]; then
		delete_repos pronosana
	fi

#	if [ ${CLUSTER_TYPE} == "minikube" ]; then
#		minikube_delete
#	fi
	
	echo "Success! Monitoring Demo setup cleanup completed."
	echo
}

# By default we start the demo & experiment and we dont expose prometheus port
prometheus=0
cluster_monitoring_setup=1
demo_monitoring_setup=1
start_demo=1
validateRecommendations=0
CLUSTER_NAME=""
bulkResults=0
# Iterate through the commandline options
while getopts o:c:d:prstaugb-: gopts
do

	 case ${gopts} in
         -)
                case "${OPTARG}" in
                        visualize)
                                visualize=1
				;;
			dataDrivenRecommendations)
				dataDrivenRecommendations=1
				;;
			monitorRecommendations)
				monitorRecommendations=1
                                ;;
			compareRecommendations)
				compareRecommendations=1
				;;
			demoBenchmark)
				demoBenchmark=1
				;;
			k8ObjectName=*)
				k8ObjectName=${OPTARG#*=}
				;;
			k8ObjectType=*)
				k8ObjectType=${OPTARG#*=}
				;;
			mode=*)
				mode=${OPTARG#*=}
				;;
			dataDir=*)
				resultsDir=${OPTARG#*=}
				;;
			summarizeClusters)
				summarizeClusters=1
				cluster_monitoring_setup=0
				demo_monitoring_setup=0
				;;
			summarizeNamespaces)
                                summarizeNamespaces=1
                                cluster_monitoring_setup=0
                                demo_monitoring_setup=0
                                ;;
			summarizeAll)
				summarizeAll=1
				cluster_monitoring_setup=0
                                demo_monitoring_setup=0
                                ;;

			clusterName=*)
				echo "checking.."
				CLUSTER_NAME=${OPTARG#*=}
				echo "clusterName is ${OPTARG#*=}"
				;;
			namespaceName=*)
				NAMESPACE_NAME=${OPTARG#*=}
				;;
			validate)
				validateRecommendations=1
				;;
			daysData=*)
				daysData=${OPTARG#*=}
				;;

                        *)
				;;
                esac
                ;;

	o)
		AUTOTUNE_DOCKER_IMAGE="${OPTARG}"
		;;
	p)
		prometheus=1
		;;
	r)
		cluster_monitoring_setup=0
		demo_monitoring_setup=1
		;;
	s)
		start_demo=1
		;;
	t)
		start_demo=0
		;;
	c)
		CLUSTER_TYPE="${OPTARG}"
		;;
	d)
		DURATION="${OPTARG}"
		;;
	a)
		cluster_monitoring_setup=0
		demo_monitoring_setup=0
		;;
	u)
		setRecommendations=1
		cluster_monitoring_setup=0
		demo_monitoring_setup=0
		;;
	g)
		getMetricsRecommendations=1
		cluster_monitoring_setup=0
		demo_monitoring_setup=0
		;;
	b)
		bulkResults=1
		;;
	*)
		usage
		;;
	esac
done

#Todo
# Options
# Generate recommendations for the data given.

# Monitor the metrics in a cluster to generate recommendations

# Benchmark specific recommendations
# Copy the previous experimentRecommendations.csv and experimentOutput.csv into another for future purpose.
if [ -e "experimentRecommendations.csv" ]; then
	mv experimentRecommendations.csv experimentRecommendations-$(date +%Y%m%d).csv
fi
if [ -e "experimentOutput.csv" ]; then
        mv experimentOutput.csv experimentOutput-$(date +%Y%m%d).csv
fi

if [ ${start_demo} -eq 1 ]; then
	monitoring_demo_start
else
	monitoring_demo_terminate
	monitoring_demo_cleanup
fi
