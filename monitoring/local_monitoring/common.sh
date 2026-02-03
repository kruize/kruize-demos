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

###########################################
#
###########################################

# Gets the absolute path to the directory
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Kruize operator deployment name constant
OPERATOR_DEPLOYMENT_NAME="kruize-operator"

function kruize_local_metric_profile() {
	export DATASOURCE="prometheus-1"
	export CLUSTER_NAME="default"
	# Metric Profile JSON
	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		resource_optimization_local_monitoring="${current_dir}/autotune/manifests/autotune/performance-profiles/resource_optimization_local_monitoring_norecordingrules.json"
	else
		resource_optimization_local_monitoring="${current_dir}/autotune/manifests/autotune/performance-profiles/resource_optimization_local_monitoring.json"
	fi
	{
		echo
		echo "#####################################################"
		echo "#     Install default metric profile"
		echo "#####################################################"
		echo
		output=$(curl -X POST http://${KRUIZE_URL}/createMetricProfile -d @$resource_optimization_local_monitoring)
		echo
	} >> "${LOG_FILE}" 2>&1

	if [[ "$output" != *"SUCCESS"* ]]; then
		echo $output >> "${LOG_FILE}" 2>&1
		false
		check_err "Error. Unable to create metric profile. Exiting!"
	fi
}

function kruize_local_metadata_profile() {

	# Metadata Profile JSON
	cluster_metadata_local_monitoring="${current_dir}/autotune/manifests/autotune/metadata-profiles/bulk_cluster_metadata_local_monitoring.json"

	{
		echo
		echo "######################################################"
		echo "#     Install metadata profile"
		echo "######################################################"
		echo
		output=$(curl -X POST http://${KRUIZE_URL}/createMetadataProfile -d @$cluster_metadata_local_monitoring)
		echo
	} >> "${LOG_FILE}" 2>&1

	if [[ "$output" != *"SUCCESS"* ]]; then
		echo $output >> "${LOG_FILE}" 2>&1
		false
		check_err "Error. Unable to create metadata profile. Exiting!"
	fi
}

function kruize_local_metadata() {
	export DATASOURCE="prometheus-1"
	export CLUSTER_NAME="default"
	{
		echo
		echo "######################################################"
		echo "#     Listing all datsources known to Kruize"
		echo "######################################################"
		echo
		curl http://"${KRUIZE_URL}"/datasources

		echo
		echo "######################################################"
		echo "#     Import metadata from prometheus-1 datasource"
		echo "######################################################"
		echo
	} >> "${LOG_FILE}" 2>&1
	output=$(curl -s --location http://"${KRUIZE_URL}"/dsmetadata \
				--header 'Content-Type: application/json' \
				--data '{
           "version": "v1.0",
           "datasource_name": "prometheus-1",
           "metadata_profile": "cluster-metadata-local-monitoring",
           "measurement_duration": "15mins"
        }')

	# Exit if unable to connect to datasource
	if [[ "$output" == *"ERROR"* ]]; then
		echo $output >> "${LOG_FILE}" 2>&1
		false
		check_err "Error. Unable to connect to datasource. Exiting!"  | tee -a "${LOG_FILE}"
		exit 1
	fi

	{
	echo
	echo "######################################################"
	echo "#     Display metadata from prometheus-1 datasource"
	echo "######################################################"
	echo
	curl "http://${KRUIZE_URL}/dsmetadata?datasource=${DATASOURCE}&verbose=true"
	echo

	echo
	echo "######################################################"
	echo "#     Display metadata for ${APP_NAMESPACE} namespace"
	echo "######################################################"
	echo
	curl "http://${KRUIZE_URL}/dsmetadata?datasource=${DATASOURCE}&cluster_name=${CLUSTER_NAME}&namespace=${APP_NAMESPACE}&verbose=true"
	echo
	} >> "${LOG_FILE}" 2>&1
}

function kruize_local_experiments() {
	{
	echo
	echo "######################################################"
	echo "#     Delete previously created experiment"
	echo "######################################################"
	echo
	for experiment in "${EXPERIMENTS[@]}"; do
		echo "curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./experiments/${experiment}.json"
		curl -X DELETE http://${KRUIZE_URL}/createExperiment -d @./experiments/${experiment}.json
    	done

	echo
	echo "######################################################"
	echo "#     Update kruize experiment jsons"
	echo "######################################################"
	echo
	for experiment in "${EXPERIMENTS[@]}"; do
		if [[ $experiment != "container_experiment_local" ]] || [[ $experiment != "namespace_experiment_local" ]]; then
			sed -i 's/"namespace": "default"/"namespace": "'"${APP_NAMESPACE}"'"/' ./experiments/${experiment}.json
		fi
	done

	echo
	} >> "${LOG_FILE}" 2>&1

	echo >> "${LOG_FILE}" 2>&1
	echo "######################################################" >> "${LOG_FILE}" 2>&1
	echo "#     Create kruize experiment" >> "${LOG_FILE}" 2>&1
	echo "######################################################" >> "${LOG_FILE}" 2>&1
	echo >> "${LOG_FILE}" 2>&1
	for experiment in "${EXPERIMENTS[@]}"; do
		experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
		experiment_type=$(grep -o '"experiment_type": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
		echo -n "🔄 Creating ${experiment_type:-container} experiment: ${experiment_name} ..."
		{
			echo "curl -X POST http://${KRUIZE_URL}/createExperiment -d @./experiments/${experiment}.json"
			curl -X POST http://${KRUIZE_URL}/createExperiment -d @./experiments/${experiment}.json
		} >> "${LOG_FILE}" 2>&1
		echo "✅ Created!"
		grep -E '"experiment_name"|"container_name"|"type"|"namespace"' experiments/${experiment}.json | grep -v '"experiment_type"' | sed -E 's/.*"experiment_name": "([^"]*)".*/\tExperiment: \1/; s/.*"type": "([^"]*)".*/\tType: \1/; s/.*"container_name": "([^"]*)".*/\tContainer: \1/; s/.*"namespace": "([^"]*)".*/\tNamespace: \1/;'
	done

	for experiment in "${EXPERIMENTS[@]}"; do
		echo >> "${LOG_FILE}" 2>&1
		echo "######################################################" >> "${LOG_FILE}" 2>&1
		echo "#     Generate recommendations for experiment: ${experiment}" >> "${LOG_FILE}" 2>&1
		echo "######################################################" >> "${LOG_FILE}" 2>&1
		echo >> "${LOG_FILE}" 2>&1
		experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
		experiment_type=$(grep -o '"experiment_type": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
		echo -n "🔄 Generating ${experiment_type:-container} recommendations for experiment: ${experiment_name} ..."
		echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}" >> "${LOG_FILE}" 2>&1
		output=$(curl -s -X POST "http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}")
		echo $output | jq >> "${LOG_FILE}" 2>&1
		echo $output | jq > "${experiment}_recommendation.json"

		if echo "$output" | grep -q "Recommendations Are Available"; then
			echo "✅ Generated! "
		else
			echo "⚠️  No recommendations generated! "
			norecommendations=1
		fi
	done
	if [[ ${norecommendations} == 1 ]]; then
		echo  | tee -a "${LOG_FILE}"
		echo "######################################################" >> "${LOG_FILE}" 2>&1
		echo "🔔 ATLEAST TWO DATAPOINTS ARE REQUIRED TO GENERATE RECOMMENDATIONS!" | tee -a "${LOG_FILE}"
		echo "🔔 PLEASE WAIT FOR FEW MINS AND GENERATE THE RECOMMENDATIONS AGAIN." | tee -a "${LOG_FILE}"
		echo "######################################################" >> "${LOG_FILE}" 2>&1
		echo >> "${LOG_FILE}" 2>&1
		echo "######################################################" >> "${LOG_FILE}" 2>&1
		echo "🔗 Generate fresh recommendations using" | tee -a "${LOG_FILE}"
		echo "######################################################" >> "${LOG_FILE}" 2>&1
		for experiment in "${EXPERIMENTS[@]}"; do
			experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
			echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}" | tee -a "${LOG_FILE}"
			echo "" >> "${LOG_FILE}" 2>&1
		done

		echo "######################################################" >> "${LOG_FILE}" 2>&1
		echo "List Recommendations using " >> "${LOG_FILE}" 2>&1
		echo "######################################################" >> "${LOG_FILE}" 2>&1
		for experiment in "${EXPERIMENTS[@]}"; do
			experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
			echo "curl -X POST http://${KRUIZE_URL}/listRecommendations?experiment_name=${experiment_name}" >> "${LOG_FILE}" 2>&1
			echo >> "${LOG_FILE}" 2>&1
		done

		echo "######################################################" >> "${LOG_FILE}" 2>&1
		echo >> "${LOG_FILE}" 2>&1
	else
		echo -n "📌 Access "| tee -a "${LOG_FILE}"
		for experiment in "${EXPERIMENTS[@]}"; do
			echo -n "${experiment}_recommendation.json " | tee -a "${LOG_FILE}"
		done
		echo -n "or Kruize UI for recommendations." | tee -a "${LOG_FILE}"
		echo ""
	fi

}

function kruize_local_demo_terminate() {
  kruize_operator=$1
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "#  Kruize Demo Terminate on ${CLUSTER_TYPE} #" | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"
	echo "Clean up in progress..."

    	if [[ "${kruize_operator}" -eq 1 ]]; then
         	 kruize_operator_cleanup $NAMESPACE >> "${LOG_FILE}" 2>&1
    	fi

      kruize_uninstall >> "${LOG_FILE}" 2>&1

	if [ ${demo} == "local" ] && [ -d "benchmarks" ]; then
		# Check if cluster is accessible before running kubectl commands with timeout
		if timeout 5 kubectl cluster-info &>/dev/null; then
			if kubectl get pods -n "${APP_NAMESPACE}" 2>/dev/null | grep -q "tfb"; then
				benchmarks_uninstall ${APP_NAMESPACE} "tfb" >> "${LOG_FILE}" 2>&1
				kill_service_port_forward "tfb-qrh-service"
			elif kubectl get pods -n "${APP_NAMESPACE}" 2>/dev/null | grep -q "human-eval"; then
				benchmarks_uninstall ${APP_NAMESPACE} "human-eval" >> "${LOG_FILE}" 2>&1
			elif kubectl get pods -n "${APP_NAMESPACE}" 2>/dev/null | grep -q "sysbench"; then
				benchmarks_uninstall ${APP_NAMESPACE} "sysbench" >> "${LOG_FILE}" 2>&1
			fi
		fi
		if [[ ${APP_NAMESPACE} != "default" ]]; then
			delete_namespace ${APP_NAMESPACE} >> "${LOG_FILE}" 2>&1
		fi
	#elif [ ${demo} == "bulk" ]; then
	#	ns_name="tfb"
	#	count=3
	#	for ((loop=1; loop<=count; loop++));
	#	do
	#		echo "Uninstalling benchmarks..."
	#		benchmarks_uninstall ${ns_name}-${loop}
	#		echo "Deleting namespaces..."
	#		delete_namespace ${ns_name}-${loop}
	#	done
	fi

  	if [ ${CLUSTER_TYPE} == "minikube" ]; then
    		minikube_delete >> "${LOG_FILE}" 2>&1
  	elif [ ${CLUSTER_TYPE} == "kind" ]; then
  	    	kill_service_port_forward "kruize"
  	    	kill_service_port_forward "kruize-ui-nginx-service"
    		kind_delete >> "${LOG_FILE}" 2>&1
  	fi

	{
		delete_repos autotune
		delete_repos "benchmarks"
	} >> "${LOG_FILE}" 2>&1
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "🕒 Success! Kruize demo cleanup took ${elapsed_time} seconds"
	echo
}

function kruize_local_demo_update() {
	# Start all the installs
	start_time=$(get_date)
	bench=$1
	if [ ${demo} == "local" ]; then
		if [ ${benchmark} -eq 1 ]; then
			echo
			create_namespace ${APP_NAMESPACE}
			benchmarks_install ${APP_NAMESPACE} ${bench} "resource_provisioning_manifests"
			echo "Success! Running the benchmark in ${APP_NAMESPACE}"
			echo
		fi
		if [ ${benchmark_load} -eq 1 ]; then
			echo
			apply_benchmark_load ${APP_NAMESPACE} ${bench} ${LOAD_DURATION}
			echo "Success! Running the benchmark load for ${LOAD_DURATION} seconds"
			echo
		fi
	elif [ ${demo} == "bulk" ]; then
		setup_workload
	fi

	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "🕒 Success! Benchmark updates took ${elapsed_time} seconds"
	echo
}

function vpa_install() {
	repo_name="autoscaler"
	vpa_dir="${current_dir}/${repo_name}/vertical-pod-autoscaler"
	vpa_down_script="${vpa_dir}/hack/vpa-down.sh"
	vpa_up_script="${vpa_dir}/hack/vpa-up.sh"
	echo
	echo "#######################################"
	echo "Cloning ${repo_name} git repos"
	if [ ! -d ${repo_name} ]; then
		git clone git@github.com:kubernetes/${repo_name}.git >/dev/null 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kubernetes/${repo_name}.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kubernetes/${repo_name} failed."
	fi
	echo "done"
	echo "#######################################"
	echo
	echo "Installing VPA..."
	if [ -d ${repo_name} ]; then
        if [ -f ${vpa_down_script} ]; then
            echo "Terminating any existing VPA installation..."
            (cd ${vpa_dir} && ./hack/vpa-down.sh >/dev/null 2>/dev/null)
		fi
		if [ -f ${vpa_up_script} ]; then
            echo "Installing VPA..."
            (cd ${vpa_dir} && ./hack/vpa-up.sh >/dev/null 2>/dev/null)
		fi
		check_err "ERROR: installation of vpa failed."
    fi
}


function update_vpa_roles() {
	manifest_file=""
	echo
	echo "#######################################"
	echo "Applying rolebindings for VPA..."
    if [ "${CLUSTER_TYPE}" == "openshift" ]; then
        manifest_file="${current_dir}/manifests/vpa_rolebinding_openshift.yaml"
    else
        manifest_file="${current_dir}/manifests/vpa_rolebinding_minikube.yaml"
    fi
	echo $manifest_file
	kubectl apply -f "${manifest_file}"
    if [ $? -ne 0 ]; then
        echo "Error applying manifest: ${manifest_file}."
	fi
}

function kruize_local_demo_setup() {
	bench=$1
	kruize_operator=$2
	
	# Start all the installs
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "# Kruize Demo Setup on ${CLUSTER_TYPE} " | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo

	# Check for both operator and kruize deployments
	echo -n "🔍 Checking if Kruize deployment is running..."
	
	# First check if cluster is accessible with timeout
	cluster_accessible=false
	if timeout 5 kubectl cluster-info &>/dev/null; then
		cluster_accessible=true
	fi

	operator_exists=false
	kruize_exists=false

	# Only check for existing deployments if cluster is accessible
	if [ "$cluster_accessible" = true ]; then
		# Check for operator deployment
		operator_deployment=$(kubectl get deployment $OPERATOR_DEPLOYMENT_NAME -n ${NAMESPACE} 2>&1)
		
		# Check for kruize pods
		kruize_pods=$(kubectl get pod -l app=kruize -n ${NAMESPACE} 2>&1)
		
		if [[ ! "$operator_deployment" =~ "NotFound" ]] && [[ ! "$operator_deployment" =~ "No resources" ]]; then
			operator_exists=true
		fi
		
		if [[ ! "$kruize_pods" =~ "NotFound" ]] && [[ ! "$kruize_pods" =~ "No resources" ]]; then
			kruize_exists=true
		fi
	fi
	
	if [ "$operator_exists" = true ] || [ "$kruize_exists" = true ]; then
		echo " Found!"
		echo -n "🔄 Cleaning up existing Kruize deployment (including database)..."
		{
		  	# Kill existing port-forwards before cleanup (only for kind cluster)
	   		if [ ${CLUSTER_TYPE} == "kind" ]; then
				kill_service_port_forward "kruize"
				kill_service_port_forward "kruize-ui-nginx-service"
				
				# Kill benchmark port-forwards if benchmark is tfb
	     			if [[ "${bench}" == "tfb" ]]; then
					kill_service_port_forward "tfb-qrh-service"
				fi
	   		fi

			# Run operator cleanup if operator exists
			if [ "$operator_exists" = true ]; then
				kruize_operator_cleanup $NAMESPACE
			fi
			
			# Check if kruize pods still exist and call kruize_uninstall if needed (only if cluster is accessible)
			if [ "$cluster_accessible" = true ]; then
				kruize_pods_after=$(kubectl get pod -l app=kruize -n ${NAMESPACE} 2>&1)
			else
				kruize_pods_after="Error: cluster not accessible"
			fi
			if [[ ! "$kruize_pods_after" =~ "NotFound" ]] && [[ ! "$kruize_pods_after" =~ "No resources" ]] && [[ ! "$kruize_pods_after" =~ "Error" ]]; then
				kruize_uninstall
			fi
		} >> "${LOG_FILE}" 2>&1
		echo "✅ Cleanup complete!"
		
		# Wait for cleanup to complete and resources to be fully removed
		echo -n "⏳ Waiting for resources to be fully removed..."
		sleep 10
		echo " Done!"
	else
		echo " Not running."
	fi

	# Clone repos if not already present
	if [ ! -d "autotune" ]; then
		echo -n "🔄 Pulling required repositories... "
		{
			clone_repos autotune
			if [[ ${#EXPERIMENTS[@]} -ne 0 ]] && [[ ${EXPERIMENTS[*]} != "container_experiment_local" ]] ; then
				clone_repos benchmarks
			fi
		} >> "${LOG_FILE}" 2>&1
		echo "✅ Done!"
	fi

	if [[ ${env_setup} -eq 1 ]]; then
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			echo -n "🔄 Installing minikube and prometheus! Please wait..."
			check_minikube
			minikube >/dev/null
			check_err "ERROR: minikube not installed"
			minikube_start
			prometheus_install autotune
			echo "✅ Installation of minikube and prometheus complete!"
		elif [ ${CLUSTER_TYPE} == "kind" ]; then
			echo -n "🔄 Installing kind and prometheus! Please wait..."
			check_kind
			kind >/dev/null
			check_err "ERROR: kind not installed"
			kind_start
			prometheus_install
			echo "✅ Installation of kind and prometheus complete!"
		fi
	elif [[ ${env_setup} -eq 0 ]]; then
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			echo -n "🔄 Checking if minikube exists..."
			check_minikube
			minikube >/dev/null
			check_err "ERROR: minikube is not available. Please install and try again!"
			echo "✅ minikube exists!"
		elif [ ${CLUSTER_TYPE} == "kind" ]; then
			echo -n "🔄 Checking if kind exists..."
			check_kind
			kind >/dev/null
			check_err "ERROR: kind is not available. Please install and try again!"
			echo "✅ kind exists!"
		fi
	fi
	if [ ${demo} == "local" ]; then
		if [[ ${#EXPERIMENTS[@]} -ne 0 ]] && [[ ${EXPERIMENTS[*]} != "container_experiment_local namespace_experiment_local" ]] ; then
			echo -n "🔄 Installing the required benchmarks..."
			create_namespace ${APP_NAMESPACE} >> "${LOG_FILE}" 2>&1
			benchmarks_install ${APP_NAMESPACE} ${bench} >> "${LOG_FILE}" 2>&1
			apply_benchmark_load ${APP_NAMESPACE} ${bench} >> "${LOG_FILE}" 2>&1
			echo "✅ Completed!"
		fi
		echo "" >> "${LOG_FILE}" 2>&1
	fi


	if [ "${vpa_install_required:-}" == "1" ]; then
	{
		echo -n "🔄 Installing VPA..."
		vpa_install >> "${LOG_FILE}" 2>&1
		echo "✅ Done!"
	}
	fi

	kruize_local_patch >> "${LOG_FILE}" 2>&1

	if [ ${demo} == "bulk" ]; then
        	kruize_local_ros_patch >> "${LOG_FILE}" 2>&1
	fi

	echo -n "🔄 Installing Kruize! Please wait..."
	kruize_start_time=$(get_date)
	if [[ "${kruize_operator}" -eq 1 ]]; then
		operator_setup >> "${LOG_FILE}" 2>&1
	else
		kruize_install >> "${LOG_FILE}" 2>&1
	fi
	install_pid=$!
	while kill -0 $install_pid 2>/dev/null;
  	do
		echo -n "."
		sleep 5
	done
	wait $install_pid
	status=$?
	if [ ${status} -ne 0 ]; then
		#echo "For detailed logs, look in ${LOG_FILE}"
		exit 1
	fi
	kruize_end_time=$(get_date)

	# port forward the urls in case of kind
	if [ ${CLUSTER_TYPE} == "kind" ]; then
		port_forward "${bench}"
	fi

	get_urls $bench $kruize_operator >> "${LOG_FILE}" 2>&1

  	# Give Kruize application time to fully initialize after pod is ready
  	echo
  	echo -n "⏳ Waiting for Kruize service to fully initialize..."
  	sleep 20
  	echo " Done!"

	echo "✅ Installation of Kruize complete!"

	if [ "${vpa_install_required:-}" == "1" ]; then
	{
		echo -n "🔄 Updating cluser-roles for VPA..."
		update_vpa_roles >> "${LOG_FILE}" 2>&1
		echo "✅ Done!"
	}
	fi

       if [ ${demo} != "bulk" ]; then
         echo -n "🔄 Installing metric profile..."
         kruize_local_metric_profile
         echo "✅ Installation of metric profile complete!"

         echo -n "🔄 Installing metadata profile..."
         kruize_local_metadata_profile
         echo "✅ Installation of metadata profile complete!"
       fi

	if [ ${demo} == "local" ]; then
		echo -n "🔄 Collecting metadata..."
		kruize_local_metadata
		echo "✅ Collection of metadata complete!"
		#kruize_local

		# Generate experiment json on local with long running container
		for experiment in "${EXPERIMENTS[@]}"; do
			if [ $experiment == "container_experiment_local" ]; then
				if [[ ${CLUSTER_TYPE} == "minikube" ]] || [[ ${CLUSTER_TYPE} == "kind" ]]; then
					# Check if prometheus port-forward already exists (kubectl or oc)
					if ! ps aux | grep -E "kubectl|oc" | grep "port-forward" | grep -q "prometheus"; then
						expose_prometheus >> "${LOG_FILE}" 2>&1 &
						sleep 5  # Give prometheus port-forward time to establish
					fi
				fi
				echo -n "🔄 Finding a long running container to create Kruize experiment..."
				generate_experiment_from_prometheus
				echo "✅ Complete!"
			fi
		done
		if [ ${#EXPERIMENTS[@]} -ne 0 ]; then
			recomm_start_time=$(get_date)
			kruize_local_experiments
			recomm_end_time=$(get_date)
		fi
	elif [ ${demo} == "bulk" ]; then
		recomm_start_time=$(get_date)
		kruize_bulk
		recomm_end_time=$(get_date)
	fi
	
	if [ "${vpa_install_required:-}" == "1" ]; then
	{
		echo "✅ Experiment has been successfully created in recreate or auto mode. No further action required."
		echo "📌 Recommendations will be generated and applied to the workloads automatically."
		echo "📌 To view the latest recommendations, run: kubectl describe vpa"
		echo "📌 To check the workload current requests and limits, run: kubectl describe pods -l app=sysbench"
	}
	fi

	show_urls $bench

	end_time=$(get_date)
	kruize_elapsed_time=$(time_diff "${kruize_start_time}" "${kruize_end_time}")
	recomm_elapsed_time=$(time_diff "${recomm_start_time}" "${recomm_end_time}")
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "🛠️ Kruize installation took ${kruize_elapsed_time} seconds"
	echo "🚀 Kruize experiment creation and recommendations generation took ${recomm_elapsed_time} seconds"
	echo "🕒 Success! Kruize demo setup took ${elapsed_time} seconds"
	echo

	if [ ${prometheus} -eq 1 ]; then
		expose_prometheus
	fi
}

#setup the operator and deploy it
operator_setup() {
      	clone_repos kruize-operator

	echo "🔄 Checking for existence of $NAMESPACE namespace"

    	if oc get ns $NAMESPACE >/dev/null 2>&1; then
          	echo "Namespace ${NAMESPACE} exists"
    	else
      		echo "Namespace ${NAMESPACE} does not exist"
      		oc create ns $NAMESPACE
      		check_err "ERROR: Failed to create $NAMESPACE namespace"
    	fi

    	echo
    	echo "🔄 Installing CRDs"
    	pushd kruize-operator  # Use pushd instead of cd
    	make install

	KRUIZE_OPERATOR_VERSION=$(grep '^VERSION' "Makefile" | awk '{print $NF}')

	if [ -z "${KRUIZE_OPERATOR_IMAGE}" ]; then
		KRUIZE_OPERATOR_IMAGE=${KRUIZE_OPERATOR_DOCKER_REPO}:${KRUIZE_OPERATOR_VERSION}
	fi

    	echo
    	echo "🔄 Deploying kruize operator image: $KRUIZE_OPERATOR_IMAGE"
    	if [ "${CLUSTER_TYPE}" == "minikube" ] || [ "${CLUSTER_TYPE}" == "kind" ]; then
    		make deploy IMG=${KRUIZE_OPERATOR_IMAGE} OVERLAY=local
    	else
    		make deploy IMG=${KRUIZE_OPERATOR_IMAGE}
    	fi
    	popd  # Return to original directory

	echo
	echo "🔄 Waiting for kruize operator to be ready"
	kubectl wait --for=condition=Available deployment/$OPERATOR_DEPLOYMENT_NAME -n $NAMESPACE --timeout=300s

	if [ -n "${KRUIZE_DOCKER_IMAGE}" ]; then
		sed -i -E 's#^([[:space:]]*)autotune_image:.*#\1autotune_image: "'"${KRUIZE_DOCKER_IMAGE}"'"#' "./kruize-operator/config/samples/v1alpha1_kruize.yaml"
	fi

	if [ -n "${KRUIZE_UI_DOCKER_IMAGE}" ]; then
		sed -i -E 's#^([[:space:]]*)autotune_ui_image:.*#\1autotune_ui_image: "'"${KRUIZE_UI_DOCKER_IMAGE}"'"#' "./kruize-operator/config/samples/v1alpha1_kruize.yaml"
	fi

	sed -i -E 's#^([[:space:]]*)cluster_type:.*#\1cluster_type: "'"${CLUSTER_TYPE}"'"#' "./kruize-operator/config/samples/v1alpha1_kruize.yaml"

	sed -i -E 's#^([[:space:]]*)namespace:.*#\1namespace: "'"${NAMESPACE}"'"#' "./kruize-operator/config/samples/v1alpha1_kruize.yaml"

	echo
	echo "📄 Applying Kruize resource..."
	pwd
	kubectl apply -f ./kruize-operator/config/samples/v1alpha1_kruize.yaml -n $NAMESPACE

	sleep 10

	echo
	echo "⏳ Waiting for all operator pods to be ready..."

	# First wait for pod to exist
	timeout=180
	elapsed=0
	while [ $elapsed -lt $timeout ]; do
		if kubectl get pod -l app=kruize-db -n $NAMESPACE --no-headers 2>/dev/null | grep -q kruize-db; then
			break
		fi
		echo -n "."
		sleep 2
		elapsed=$((elapsed + 2))
	done

	if [ $elapsed -ge $timeout ]; then
		echo "❌ Timeout waiting for kruize-db pod to be created"
		kubectl get pods -n $NAMESPACE
		exit 1
	fi

    	echo "⏳ Waiting for kruize-db pod to be ready..."
    	kubectl wait --for=condition=Ready pod -l app=kruize-db -n $NAMESPACE --timeout=600s
    	if [ $? -ne 0 ]; then
        	echo "❌ Kruize-db pod failed to become ready"
        	kubectl get pods -n $NAMESPACE
        	kubectl describe pod -l app=kruize-db -n $NAMESPACE
        	exit 1
    	fi

	# First wait for pod to exist
	timeout=180
	elapsed=0
	while [ $elapsed -lt $timeout ]; do
		if kubectl get pod -l app=kruize -n $NAMESPACE --no-headers 2>/dev/null | grep -q kruize; then
			break
		fi
		echo -n "."
		sleep 2
		elapsed=$((elapsed + 2))
	done

	if [ $elapsed -ge $timeout ]; then
		echo "❌ Timeout waiting for kruize pod to be created"
		kubectl get pods -n $NAMESPACE
		exit 1
	fi

	kubectl wait --for=condition=Ready pod -l app=kruize -n $NAMESPACE --timeout=600s
    	if [ $? -ne 0 ]; then
        	echo "❌ Kruize pod failed to become ready"
        	kubectl get pods -n $NAMESPACE
        	kubectl describe pod -l app=kruize -n $NAMESPACE
        	exit 1
    	fi

	echo "⏳ Waiting for kruize-ui pod to be ready..."
	# First wait for pod to exist
	timeout=180
	elapsed=0
	while [ $elapsed -lt $timeout ]; do
		if kubectl get pod -l app=kruize-ui-nginx -n $NAMESPACE --no-headers 2>/dev/null | grep -q kruize-ui-nginx; then
			break
		fi
		echo -n "."
		sleep 2
		elapsed=$((elapsed + 2))
	done

	if [ $elapsed -ge $timeout ]; then
		echo "❌ Timeout waiting for kruize-ui pod to be created"
		kubectl get pods -n $NAMESPACE
		exit 1
	fi


    	echo "⏳ Waiting for kruize-ui pod to be ready..."
    	kubectl wait --for=condition=Ready pod -l app=kruize-ui-nginx -n $NAMESPACE --timeout=600s
    	if [ $? -ne 0 ]; then
        	echo "❌ kruize-ui-nginx pod failed to become ready"
        	kubectl get pods -n $NAMESPACE
        	kubectl describe pod -l app=kruize-ui-nginx -n $NAMESPACE
        	exit 1
    	fi
    	echo "✅ All Kruize application pods are ready!"

 	echo "✅ Deployment complete! Checking status..."
 	kubectl get kruize -n $NAMESPACE
 	kubectl get pods -n $NAMESPACE

 	echo
	echo "⏳ Waiting for Kruize service to be accessible..."
 	# Loops until the service has at least one backend IP assigned
 	until { kubectl get endpoints kruize -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null; \
        kubectl get endpoints kruize-service -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null; } \
        | grep -q .; do
   		echo "Waiting for kruize or kruize-service endpoints..."
   		sleep 5
  	done
 	echo "Service is wired to pods!"

  	echo
 	echo "🔍 To view operator logs:"
 	echo "kubectl logs deployment/$OPERATOR_DEPLOYMENT_NAME -n $NAMESPACE -f"
}

# Gnerate experiment with the container which is long running
# Gathering top 10 container details by default. But using only one for now.
generate_experiment_from_prometheus() {
	if [ ${CLUSTER_TYPE} == "minikube" ] || [ ${CLUSTER_TYPE} == "kind" ]; then
		PROMETHEUS_URL="localhost:9090"
		TOKEN="TOKEN"
	else
		PROMETHEUS_URL=$(oc get route prometheus-k8s -n openshift-monitoring -o jsonpath='{.spec.host}')
		TOKEN=$(oc whoami -t)
	fi

	if [[ -z "$PROMETHEUS_URL" ]]; then
		check_err "Error: Could not retrieve Prometheus URL to generate the experiment json. Ensure you are connected to the cluster and that Prometheus is available. Exiting!"
	fi

	if [ ${CLUSTER_TYPE} == "minikube" ] || [ ${CLUSTER_TYPE} == "kind" ]; then
		PROMETHEUS_URL="http://$PROMETHEUS_URL/api/v1/query"
	elif [ ${CLUSTER_TYPE} == "openshift" ]; then
		PROMETHEUS_URL="https://$PROMETHEUS_URL/api/v1/query"
	fi

	# Prometheus query
	QUERY='
  topk(10,
  (time() - container_start_time_seconds{container!="POD", container!=""})
  * on(pod, container, namespace)
  group_left(workload, workload_type) (
  max(kube_pod_container_info{container!="", container!="POD", pod!=""}) by (pod, container, namespace)
  )
  * on(pod, namespace) group_left(workload, workload_type) (
  max(namespace_workload_pod:kube_pod_owner:relabel{pod!=""}) by (pod, namespace, workload, workload_type)
  )
  )
  '

	# Send the query to Prometheus with the token and capture the response
	response=$(curl -s -k -G --header "Authorization: Bearer $TOKEN" --data-urlencode "query=${QUERY}" "${PROMETHEUS_URL}")

	# Extract the first row from the result using jq
	first_row=$(echo "$response" | jq -r '.data.result[0]')

	# Check if the result is empty
	if [[ -z "$first_row" || "$first_row" == "null" ]]; then
		false
		check_err "Error: No data returned from Prometheus query to create experiments. Exiting!"
	fi

	# Extract the required fields (workload, workload_type, container, namespace, pod)
	workload=$(echo "$first_row" | jq -r '.metric.workload // "unknown"')
	workload_type=$(echo "$first_row" | jq -r '.metric.workload_type // "unknown"')
	container=$(echo "$first_row" | jq -r '.metric.container // "unknown"')
	namespace=$(echo "$first_row" | jq -r '.metric.namespace // "unknown"')
	image=$(echo "$first_row" | jq -r '.metric.image // "unknown"')

	for field in workload workload_type container namespace; do
		if [ "${!field}" == "unknown" ]; then
			false
			check_err "Error: Unable to get the details for the experiment. Exiting."
		fi
	done

	#experiment_name="${container}_${namespace}_${workload}_${workload_type}"
	# Keeping it simple for easy reference
	#experiment_name="monitor_${container}"

	template_json="experiments/experiment_template.json"
	container_json="experiments/container_experiment_local.json"
	nsp_template_json="experiments/namespace_experiment_template.json"
	namespace_json="experiments/namespace_experiment_local.json"

	cp "$template_json" "$container_json"
	cp "$nsp_template_json" "$namespace_json"

	# Use sed to replace placeholders with actual values in the new JSON file
sed -i \
	-e "s/PLACEHOLDER_WORKLOAD_TYPE/$workload_type/g" \
	-e "s/PLACEHOLDER_WORKLOAD/$workload/g" \
	-e "s/PLACEHOLDER_CONTAINER/$container/g" \
	-e "s/PLACEHOLDER_NAMESPACE_NAME/$namespace/g" \
	-e "s/PLACEHOLDER_IMAGE/$namespace/g" \
	"$container_json"

sed -i \
        -e "s/PLACEHOLDER_NAMESPACE_NAME/$namespace/g" \
        "$namespace_json"

}

#  Kruize Operator Cleanup
function kruize_operator_cleanup() {
	local namespace="${1:-openshift-tuning}"
	local kubectl_cmd="kubectl"

	# Use oc command for OpenShift, kubectl for other clusters
	if [ "${CLUSTER_TYPE}" == "openshift" ]; then
		kubectl_cmd="oc"
	fi

	echo
	echo "#######################################"
	echo "Cleaning up Kruize Operator resources"
	echo "#######################################"

	# Check if operator deployment exists in the cluster
	if ${kubectl_cmd} get deployment $OPERATOR_DEPLOYMENT_NAME -n $namespace >/dev/null 2>&1; then
		echo "Kruize Operator deployment found. Undeploying..."

		# Delete Kruize custom resources
		echo "Deleting Kruize custom resources..."
		${kubectl_cmd} delete kruize --all -n ${namespace} 2>/dev/null || true
		
		# Delete the operator deployment
		echo "Deleting operator deployment..."
		${kubectl_cmd} delete deployment $OPERATOR_DEPLOYMENT_NAME -n $namespace 2>/dev/null || true
		
		# Delete any kruize deployments in the namespace
		echo "Deleting kruize deployments in namespace ${namespace}..."
		${kubectl_cmd} delete deployment -l app=kruize -n ${namespace} 2>/dev/null || true
		${kubectl_cmd} delete deployment -l app=kruize-db -n ${namespace} 2>/dev/null || true
		
		# Wait for all kruize pods to terminate
		echo -n "Waiting for all kruize pods to terminate..."
		${kubectl_cmd} wait --for=delete pod -l app=kruize -n ${namespace} --timeout=60s 2>/dev/null || true
		${kubectl_cmd} wait --for=delete pod -l app=kruize-db -n ${namespace} --timeout=60s 2>/dev/null || true
		echo "Done!"
		echo
		
		# Delete Kruize CRDs (after CRs and pods are deleted)
		echo "Deleting Kruize CRD..."
		${kubectl_cmd} delete crd kruizes.kruize.io 2>/dev/null || true
		sleep 10

		# Delete ServiceAccounts in kruize namespace
		kruize_serviceaccounts=$(${kubectl_cmd} get serviceaccount -n $namespace 2>/dev/null | grep kruize | awk '{print $1}')
		if [ -n "$kruize_serviceaccounts" ]; then
			echo "$kruize_serviceaccounts" | xargs ${kubectl_cmd} delete serviceaccount -n $namespace 2>/dev/null || true
		else
			echo "No kruize-related ServiceAccounts found"
		fi

		# Delete Services in kruize namespace
		kruize_services=$(${kubectl_cmd} get service -n $namespace 2>/dev/null | grep kruize | awk '{print $1}')
		if [ -n "$kruize_services" ]; then
			echo "$kruize_services" | xargs ${kubectl_cmd} delete service -n $namespace 2>/dev/null || true
		else
			echo "No kruize-related Services found"
		fi

		# Delete RoleBindings before Roles
		kruize_rolebindings=$(${kubectl_cmd} get rolebinding -n $namespace 2>/dev/null | grep kruize | awk '{print $1}')
		if [ -n "$kruize_rolebindings" ]; then
			echo "$kruize_rolebindings" | xargs ${kubectl_cmd} delete rolebinding -n $namespace 2>/dev/null || true
		else
			echo "No kruize-related RoleBindings found"
		fi

		# Delete Roles
		kruize_roles=$(${kubectl_cmd} get role -n $namespace 2>/dev/null | grep kruize | awk '{print $1}')
		if [ -n "$kruize_roles" ]; then
			echo "$kruize_roles" | xargs ${kubectl_cmd} delete role -n $namespace 2>/dev/null || true
		else
			echo "No kruize-related Roles found"
		fi

		# Delete ClusterRoleBindings before ClusterRoles
		kruize_clusterrolebindings=$(${kubectl_cmd} get clusterrolebinding 2>/dev/null | grep kruize | awk '{print $1}')
		if [ -n "$kruize_clusterrolebindings" ]; then
			echo "$kruize_clusterrolebindings" | xargs ${kubectl_cmd} delete clusterrolebinding 2>/dev/null || true
		else
			echo "No kruize-related ClusterRoleBindings found"
		fi

		# Delete specific ClusterRoleBindings
		${kubectl_cmd} delete clusterrolebinding instaslices-access-binding 2>/dev/null || true
		${kubectl_cmd} delete clusterrolebinding autotune-scc-crb 2>/dev/null || true

		# Delete ClusterRoles
		kruize_clusterroles=$(${kubectl_cmd} get clusterrole 2>/dev/null | grep kruize | awk '{print $1}')
		if [ -n "$kruize_clusterroles" ]; then
			echo "$kruize_clusterroles" | xargs ${kubectl_cmd} delete clusterrole 2>/dev/null || true
		else
			echo "No kruize-related ClusterRoles found"
		fi

		# Delete specific ClusterRoles
		${kubectl_cmd} delete clusterrole instaslices-access 2>/dev/null || true

		# Delete ConfigMaps in kruize namespace
		${kubectl_cmd} delete configmap kruizeconfig -n ${namespace} 2>/dev/null || true

		# Delete StorageClass (only for OpenShift)
		if [ "${CLUSTER_TYPE}" == "openshift" ]; then
		  	${kubectl_cmd} delete storageclass manual 2>/dev/null || true
		fi

		# Clean up kruize-operator directory if it exists
		if [ -d "kruize-operator" ]; then
			rm -rf kruize-operator
		fi
		echo

		local db_pv_name
		local db_pvc_name

		if [ "${CLUSTER_TYPE}" == "openshift" ]; then
		  db_pv_name="kruize-db-pv-volume"
		  db_pvc_name="kruize-db-pv-claim"
		else
		  db_pv_name="kruize-db-pv"
		  db_pvc_name="kruize-db-pvc"
		fi

		# Check if PVC exists before attempting deletion
		if ${kubectl_cmd} get pvc $db_pvc_name -n ${namespace} >/dev/null 2>&1; then
			echo "Deleting database PVC to clear existing data..."
			${kubectl_cmd} delete pvc $db_pvc_name -n ${namespace} 2>/dev/null || echo "Failed to delete PVC $db_pvc_name"
			echo

			# Wait for PVC to be fully deleted
			echo "Waiting for PVC to be fully deleted..."
			timeout=120
			elapsed=0
			while ${kubectl_cmd} get pvc $db_pvc_name -n ${namespace} >/dev/null 2>&1; do
				if [ $elapsed -ge $timeout ]; then
					echo "Warning: Timeout waiting for PVC deletion after ${timeout}s, continuing anyway..."
					break
				fi
				echo -n "."
				sleep 5
				elapsed=$((elapsed + 5))
			done
			echo "Database PVC deleted successfully"
			echo
		else
			echo "PVC $db_pvc_name not found or already deleted"
			echo
		fi

		echo "Deleting database PV to clear existing data..."
		# Check if PV exists before attempting deletion
		if ${kubectl_cmd} get pv $db_pv_name >/dev/null 2>&1; then
			${kubectl_cmd} delete pv $db_pv_name --wait=false 2>/dev/null || echo "PV $db_pv_name deletion initiated"
			echo

			# Wait for PV to be fully deleted
			echo "Waiting for PV to be fully deleted..."
			timeout=60
			elapsed=0
			while ${kubectl_cmd} get pv $db_pv_name >/dev/null 2>&1; do
				if [ $elapsed -ge $timeout ]; then
					echo
					echo "Warning: Timeout waiting for PV deletion after ${timeout}s"
					echo "PV may be stuck in 'Terminating' state. Attempting to force delete..."
					${kubectl_cmd} patch pv $db_pv_name -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
					sleep 5
					if ${kubectl_cmd} get pv $db_pv_name >/dev/null 2>&1; then
						echo "Warning: PV still exists after force delete attempt, continuing anyway..."
					fi
					break
				fi
				echo -n "."
				sleep 5
				elapsed=$((elapsed + 5))
			done
			echo "Database PV deleted successfully"
			echo
		else
			echo "PV $db_pv_name not found or already deleted"
			echo
		fi
	else
		echo "$OPERATOR_DEPLOYMENT_NAME deployment not found, skipping cleanup"
	fi

	echo "Kruize Operator cleanup complete!"
	echo "#######################################"
	echo
}

# Check if Go is installed and meets minimum version requirement
check_go_prerequisite() {
	echo -n "🔍 Pre-req check: Verifying Go for operator deployment..."

	# Check if go is in PATH
	if ! command -v go >/dev/null 2>&1; then
		echo "❌ ERROR: Go is not installed or not in PATH"
		echo "   Go (v1.21.0+) is REQUIRED to deploy the operator"
		echo "   Please install Go from: https://go.dev/doc/install"
		return 1
	fi

	# Get Go version
	GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
	echo "Found Go version: ${GO_VERSION}" >> ${LOG_FILE}

	# Check if version meets minimum requirement (v1.21.0+)
	REQUIRED_VERSION="1.21.0"

	# Compare versions using sort -V
	if printf '%s\n%s\n' "${REQUIRED_VERSION}" "${GO_VERSION}" | sort -V -C; then
		echo "Go version ${GO_VERSION} meets minimum requirement (v${REQUIRED_VERSION}+)" >> ${LOG_FILE}
		echo " Done!"
		return 0
	else
		echo "❌ ERROR: Go version ${GO_VERSION} does not meet minimum requirement (v${REQUIRED_VERSION}+)"
		echo " Please upgrade Go from: https://go.dev/doc/install"
		return 1
	fi
}
