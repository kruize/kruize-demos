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
           "datasource_name": "prometheus-1"
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
			#sed -i "s/"namespace": "default"/"namespace": "${APP_NAMESPACE}"/" ./experiments/${experiment}.json
			sed -i 's/"namespace_name": "default"/"namespace_name": "'"${APP_NAMESPACE}"'"/' ./experiments/${experiment}.json
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
		grep -E '"experiment_name"|"container_name"|"type"|"namespace"|"namespace_name"' experiments/${experiment}.json | grep -v '"experiment_type"' | sed -E 's/.*"experiment_name": "([^"]*)".*/\tExperiment: \1/; s/.*"type": "([^"]*)".*/\tType: \1/; s/.*"container_name": "([^"]*)".*/\tContainer: \1/; s/.*"namespace": "([^"]*)".*/\tNamespace: \1/; s/.*"namespace_name": "([^"]*)".*/\tNamespace: \1/'
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
		echo -n "or kruize UI for recommendations." | tee -a "${LOG_FILE}"
		echo ""
	fi

}

function kruize_local_demo_terminate() {
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "#  Kruize Demo Terminate on ${CLUSTER_TYPE} #" | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"
	echo "Clean up in progress..."

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube_delete >> "${LOG_FILE}" 2>&1
	elif [ ${CLUSTER_TYPE} == "kind" ]; then
		kind_delete >> "${LOG_FILE}" 2>&1
	else
		kruize_uninstall
	fi
	if [ ${demo} == "local" ] && [ -d "benchmarks" ]; then
		if kubectl get pods -n "${APP_NAMESPACE}" | grep -q "tfb"; then
			benchmarks_uninstall ${APP_NAMESPACE} "tfb" >> "${LOG_FILE}" 2>&1
		elif kubectl get pods -n "${APP_NAMESPACE}" | grep -q "human-eval"; then
			benchmarks_uninstall ${APP_NAMESPACE} "human-eval" >> "${LOG_FILE}" 2>&1
		elif kubectl get pods -n "${APP_NAMESPACE}" | grep -q "sysbench"; then
			benchmarks_uninstall ${APP_NAMESPACE} "sysbench" >> "${LOG_FILE}" 2>&1
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
	# Start all the installs
	start_time=$(get_date)
	echo | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo "# Kruize Demo Setup on ${CLUSTER_TYPE} " | tee -a "${LOG_FILE}"
	echo "#######################################" | tee -a "${LOG_FILE}"
	echo

	echo -n "🔄 Pulling required repositories... "
	{
		clone_repos autotune
		if [[ ${#EXPERIMENTS[@]} -ne 0 ]] && [[ ${EXPERIMENTS[*]} != "container_experiment_local" ]] ; then
			clone_repos benchmarks
		fi
	} >> "${LOG_FILE}" 2>&1
	echo "✅ Done!"
	if [[ ${env_setup} -eq 1 ]]; then
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			echo -n "🔄 Installing minikube and prometheus! Please wait..."
			sys_cpu_mem_check
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

	echo -n "🔄 Installing kruize! Please wait..."
	kruize_start_time=$(get_date)
	if [ ${CLUSTER_TYPE} != "local" ]; then
	  kruize_install &
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
		port_forward
	fi
	{
		get_urls $bench
	} >> "${LOG_FILE}" 2>&1
	echo "✅ Installation of kruize complete!"

	if [ "${vpa_install_required:-}" == "1" ]; then
	{
		echo -n "🔄 Updating cluser-roles for VPA..."
		update_vpa_roles >> "${LOG_FILE}" 2>&1
		echo "✅ Done!"
	}
	fi

	echo -n "🔄 Installing metric profile..."
	kruize_local_metric_profile
	echo "✅ Installation of metric profile complete!"

	if [ ${demo} == "local" ]; then
		echo -n "🔄 Collecting metadata..."
		kruize_local_metadata
		echo "✅ Collection of metadata complete!"
		#kruize_local

		# Generate experiment json on local with long running container
		for experiment in "${EXPERIMENTS[@]}"; do
			if [ $experiment == "container_experiment_local" ]; then
				if [[ ${CLUSTER_TYPE} == "minikube" ]] || [[ ${CLUSTER_TYPE} == "kind" ]]; then
					expose_prometheus >> "${LOG_FILE}" 2>&1 &
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

