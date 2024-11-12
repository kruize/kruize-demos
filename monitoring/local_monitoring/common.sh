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
        echo "######################################################"
        echo "#     Install default metric profile"
        echo "######################################################"
        echo
        curl -X POST http://${KRUIZE_URL}/createMetricProfile -d @$resource_optimization_local_monitoring
        echo
        } >> "${LOG_FILE}" 2>&1

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
		echo "Unable to connect to datasource. Exiting!"  | tee -a "${LOG_FILE}"
		echo $output >> "${LOG_FILE}" 2>&1
		echo "For detailed logs, look in ${LOG_FILE}"
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
		if [[ $experiment != "container_experiment_local" ]]; then
			sed -i 's/"namespace": "default"/"namespace": "'"${APP_NAMESPACE}"'"/' ./experiments/${experiment}.json
			sed -i 's/"namespace_name": "default"/"namespace_name": "'"${APP_NAMESPACE}"'"/' ./experiments/${experiment}.json
		fi
        done

	echo
	} >> "${LOG_FILE}" 2>&1

	echo | tee -a "${LOG_FILE}"
	echo "######################################################" | tee -a "${LOG_FILE}"
	echo "#     Create kruize experiment" | tee -a "${LOG_FILE}"
	echo "######################################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"
	for experiment in "${EXPERIMENTS[@]}"; do
		{
		echo "curl -X POST http://${KRUIZE_URL}/createExperiment -d @./experiments/${experiment}.json"
		curl -X POST http://${KRUIZE_URL}/createExperiment -d @./experiments/${experiment}.json
		} >> "${LOG_FILE}" 2>&1

        done
	echo "✅ Creating kruize experiments complete!"

	apply_benchmark_load ${APP_NAMESPACE} >> "${LOG_FILE}" 2>&1

	for experiment in "${EXPERIMENTS[@]}"; do
		echo | tee -a "${LOG_FILE}"
		echo "######################################################" | tee -a "${LOG_FILE}"
		echo "#     Generate recommendations for experiment: ${experiment}" | tee -a "${LOG_FILE}"
		echo "######################################################" | tee -a "${LOG_FILE}"
		echo | tee -a "${LOG_FILE}"
		experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')	
		echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}" >> "${LOG_FILE}" 2>&1
		curl -s -X POST "http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}" | tee -a "${LOG_FILE}"
        done
	echo
	if [[ ${#EXPERIMENTS[@]} -ne 0 ]]; then
		echo "✅ Generating recommendations for all experiments complete!"
	fi

	echo "" | tee -a "${LOG_FILE}"
	echo "######################################################" | tee -a "${LOG_FILE}"
	echo "🔔 ATLEAST TWO DATAPOINTS ARE REQUIRED TO GENERATE RECOMMENDATIONS!" | tee -a "${LOG_FILE}"
	echo "🔔 PLEASE WAIT FOR FEW MINS AND GENERATE THE RECOMMENDATIONS AGAIN IF NO RECOMMENDATIONS ARE AVAILABLE!" | tee -a "${LOG_FILE}"
	echo "######################################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"

	echo "######################################################" | tee -a "${LOG_FILE}"
	echo "Generate fresh recommendations using" | tee -a "${LOG_FILE}"
	echo "######################################################" | tee -a "${LOG_FILE}"
	for experiment in "${EXPERIMENTS[@]}"; do
                experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
                echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}" | tee -a "${LOG_FILE}"
        done
	echo "" | tee -a "${LOG_FILE}"

	echo "######################################################" | tee -a "${LOG_FILE}"
  	echo "List Recommendations using " | tee -a "${LOG_FILE}"
	echo "######################################################" | tee -a "${LOG_FILE}"
	for experiment in "${EXPERIMENTS[@]}"; do
                experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
                echo "curl -X POST http://${KRUIZE_URL}/listRecommendations?experiment_name=${experiment_name}" | tee -a "${LOG_FILE}"
        done
	
	echo | tee -a "${LOG_FILE}"
  	echo "######################################################" | tee -a "${LOG_FILE}"
  	echo | tee -a "${LOG_FILE}"
}

function kruize_local_demo_terminate() {
        start_time=$(get_date)
        echo | tee -a "${LOG_FILE}"
        echo "#######################################" | tee -a "${LOG_FILE}"
        echo "#       Kruize Demo Terminate         #" | tee -a "${LOG_FILE}"
        echo "#######################################" | tee -a "${LOG_FILE}"
        echo | tee -a "${LOG_FILE}"
        echo "Cleaning up in progress..."

        if [ ${CLUSTER_TYPE} == "minikube" ]; then
                minikube_delete >> "${LOG_FILE}" 2>&1
        elif [ ${CLUSTER_TYPE} == "kind" ]; then
                kind_delete >> "${LOG_FILE}" 2>&1
        else
                kruize_uninstall
        fi
        if [ ${demo} == "local" ]; then
                benchmarks_uninstall ${APP_NAMESPACE} "tfb" >> "${LOG_FILE}" 2>&1
                benchmarks_uninstall ${APP_NAMESPACE} "human-eval" >> "${LOG_FILE}" 2>&1
                if [[ ${APP_NAMESPACE} != "default" ]]; then
                        delete_namespace ${APP_NAMESPACE} >> "${LOG_FILE}" 2>&1
                fi
        elif [ ${demo} == "bulk" ]; then
                ns_name="tfb"
                count=3
                for ((loop=1; loop<=count; loop++));
                do
                        echo "Uninstalling benchmarks..."
                        benchmarks_uninstall ${ns_name}-${loop}
                        echo "Deleting namespaces..."
                        delete_namespace ${ns_name}-${loop}
                done
        fi
        {
        delete_repos autotune
        delete_repos "benchmarks"
        } >> "${LOG_FILE}" 2>&1
        end_time=$(get_date)
        elapsed_time=$(time_diff "${start_time}" "${end_time}")
        echo "Success! Kruize demo cleanup took ${elapsed_time} seconds"
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
        echo "Success! Benchmark updates took ${elapsed_time} seconds"
        echo
}

function kruize_local_demo_setup() {
        bench=$1
        # Start all the installs
        start_time=$(get_date)
        echo | tee -a "${LOG_FILE}"
        echo "#######################################" | tee -a "${LOG_FILE}"
        echo "#       Kruize Local Demo Setup       #" | tee -a "${LOG_FILE}"
        echo "#######################################" | tee -a "${LOG_FILE}"
        echo

        if [ ${kruize_restart} -eq 0 ]; then
                {
                clone_repos autotune
                clone_repos benchmarks
                } >> "${LOG_FILE}" 2>&1
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
                if [ ${demo} == "local" ]; then
                        {
                        create_namespace ${APP_NAMESPACE}
                        if [ ${#EXPERIMENTS[@]} -ne 0 ]; then
                                benchmarks_install ${APP_NAMESPACE} ${bench}
                        fi
                        echo ""
                        } >> "${LOG_FILE}" 2>&1
                fi
        fi
        {
        kruize_local_patch
        } >> "${LOG_FILE}" 2>&1
        echo -n "🔄 Installing kruize! Please wait..."
        kruize_install &
        install_pid=$!
        while kill -0 $install_pid 2>/dev/null; do
                echo -n "."
                sleep 5
        done
        wait $install_pid
        status=$?
        if [ ${status} -ne 0 ]; then
		echo "For detailed logs, look in ${LOG_FILE}"
                exit 1
        fi

        {
        echo
        # port forward the urls in case of kind
        if [ ${CLUSTER_TYPE} == "kind" ]; then
                port_forward
        fi

        get_urls
        } >> "${LOG_FILE}" 2>&1
	echo "✅ Installation of kruize complete!"

        if [ ${demo} == "local" ]; then
		echo -n "🔄 Installing metric profile..."
		kruize_local_metric_profile
                echo "✅ Installation of metric profile complete!"
		echo -n "🔄 Collecting metadata..."
		kruize_local_metadata
		echo "✅ Collection of metadata complete!"
                #kruize_local

		# Generate experiment for local with long running container
		for experiment in "${EXPERIMENTS[@]}"; do
			if [ $experiment == "container_experiment_local" ]; then
				expose_prometheus >> "${LOG_FILE}" 2>&1 &
				generate_experiment_from_prometheus
			fi
		done
                if [ ${#EXPERIMENTS[@]} -ne 0 ]; then
                        kruize_local_experiments
                fi
                show_urls $bench
        elif [ ${demo} == "bulk" ]; then
                kruize_bulk
        fi

        end_time=$(get_date)
        elapsed_time=$(time_diff "${start_time}" "${end_time}")
        echo "Success! Kruize demo setup took ${elapsed_time} seconds"
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
    echo "Error: Could not retrieve Prometheus URL. Ensure you are connected to the cluster and that Prometheus is available."
    return 1
  fi

  if [[ -z "$TOKEN" ]]; then
    echo "Error: Could not retrieve OpenShift authentication token. Please log in using 'oc login'."
    return 1
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
    echo "Error: No data returned from Prometheus query to create experiments. Exiting!"
    exit 1
  fi

  # Extract the required fields (workload, workload_type, container, namespace, pod)
  workload=$(echo "$first_row" | jq -r '.metric.workload // "unknown"')
  workload_type=$(echo "$first_row" | jq -r '.metric.workload_type // "unknown"')
  container=$(echo "$first_row" | jq -r '.metric.container // "unknown"')
  namespace=$(echo "$first_row" | jq -r '.metric.namespace // "unknown"')
  image=$(echo "$first_row" | jq -r '.metric.image // "unknown"')

  experiment_name="${container}_${namespace}_${workload}_${workload_type}"

  template_json="experiments/experiment_template.json"
  new_json="experiments/container_experiment_local.json"

  cp "$template_json" "$new_json"

  # Use sed to replace placeholders with actual values in the new JSON file
sed -i \
    -e "s/PLACEHOLDER_EXPERIMENT_NAME/$experiment_name/g" \
    -e "s/PLACEHOLDER_WORKLOAD_TYPE/$workload_type/g" \
    -e "s/PLACEHOLDER_WORKLOAD/$workload/g" \
    -e "s/PLACEHOLDER_CONTAINER/$container/g" \
    -e "s/PLACEHOLDER_NAMESPACE_NAME/$namespace/g" \
    -e "s/PLACEHOLDER_IMAGE/$namespace/g" \
    "$new_json"
}

