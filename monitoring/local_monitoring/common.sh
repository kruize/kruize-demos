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

function kruize_local() {
	export DATASOURCE="prometheus-1"
        export CLUSTER_NAME="default"
	if [ ${THANOS} == 1 ]; then
		export DATASOURCE="thanos"
	        export CLUSTER_NAME="eu-1"
	fi

        # Metric Profile JSON
        if [ ${CLUSTER_TYPE} == "minikube" ]; then
                resource_optimization_local_monitoring="${current_dir}/autotune/manifests/autotune/performance-profiles/resource_optimization_local_monitoring_norecordingrules.json"
        else
                resource_optimization_local_monitoring="${current_dir}/autotune/manifests/autotune/performance-profiles/resource_optimization_local_monitoring.json"
        fi

        {
        echo
        echo "######################################################"
        echo "#     Listing all datsources known to Kruize"
        echo "######################################################"
        echo
        curl http://"${KRUIZE_URL}"/datasources

        echo
        echo "######################################################"
        echo "#     Import metadata from $DATASOURCE datasource"
        echo "######################################################"
        echo
	if [ ${THANOS} == 0 ]; then
	        curl --location http://"${KRUIZE_URL}"/dsmetadata \
        	--header 'Content-Type: application/json' \
	        --data '{
        	   "version": "v1.0",
	           "datasource_name": "prometheus-1"
        	}'
	else
	        curl --location http://"${KRUIZE_URL}"/dsmetadata \
        	--header 'Content-Type: application/json' \
	        --data '{
        	   "version": "v1.0",
	           "datasource_name": "thanos"
        	}'
	fi

        echo
        echo "######################################################"
        echo "#     Display metadata from ${DATASOURCE} datasource"
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

	echo
        echo "######################################################"
        echo "#     Install default metric profile"
        echo "######################################################"
        echo
        curl -X POST http://${KRUIZE_URL}/createMetricProfile -d @$resource_optimization_local_monitoring
        echo

	if [ ${THANOS} == 1 ]; then
		echo
        	echo "######################################################"
	        echo "#     Create kruize experiment"
        	echo "######################################################"
	        echo
        	echo "curl -X POST http://${KRUIZE_URL}/createExperiment -d @./experiments/create_thanos_exp.json"
	        curl -X POST http://${KRUIZE_URL}/createExperiment -d @./experiments/create_thanos_exp.json
        	echo

	        echo "Sleeping for 30s before generating the recommendations!"
        	sleep 30s

	        echo
        	echo "######################################################"
	        echo "#     Generate recommendations for every experiment"
        	echo "######################################################"
	        echo
        	curl -X POST "http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_tfb_benchmark"
	        echo ""

        	echo
	        echo "######################################################"
        	echo
	        echo "Generate fresh recommendations using"
        	echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=monitor_tfb_benchmark"
	        echo
        	echo "List Recommendations using "
	        echo "curl http://${KRUIZE_URL}/listRecommendations?experiment_name=monitor_tfb_benchmark"
        	echo
	        echo "######################################################"
        	echo
	fi


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
		sed -i 's/"namespace": "default"/"namespace": "'"${APP_NAMESPACE}"'"/' ./experiments/${experiment}.json
		sed -i 's/"namespace_name": "default"/"namespace_name": "'"${APP_NAMESPACE}"'"/' ./experiments/${experiment}.json
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

	apply_benchmark_load ${APP_NAMESPACE} >> "${LOG_FILE}" 2>&1

	echo | tee -a "${LOG_FILE}"
  	echo "######################################################" | tee -a "${LOG_FILE}"
  	echo "#     Generate recommendations for every experiment" | tee -a "${LOG_FILE}"
  	echo "######################################################" | tee -a "${LOG_FILE}"
  	echo | tee -a "${LOG_FILE}"

	for experiment in "${EXPERIMENTS[@]}"; do
		experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')	
		echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}" >> "${LOG_FILE}" 2>&1
		curl -X POST "http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}" | tee -a "${LOG_FILE}"
        done

	echo "" | tee -a "${LOG_FILE}"
	echo "######################################################" | tee -a "${LOG_FILE}"
	echo "ATLEAST TWO DATAPOINTS ARE REQUIRED TO GENERATE RECOMMENDATIONS!" | tee -a "${LOG_FILE}"
	echo "PLEASE WAIT FOR FEW MINS AND GENERATE THE RECOMMENDATIONS AGAIN IF NO RECOMMENDATIONS ARE AVAILABLE!" | tee -a "${LOG_FILE}"
	echo "######################################################" | tee -a "${LOG_FILE}"
	echo | tee -a "${LOG_FILE}"

  	echo "Generate fresh recommendations using" | tee -a "${LOG_FILE}"
	for experiment in "${EXPERIMENTS[@]}"; do
                experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
                echo "curl -X POST http://${KRUIZE_URL}/generateRecommendations?experiment_name=${experiment_name}" | tee -a "${LOG_FILE}"
        done

  	echo "List Recommendations using " | tee -a "${LOG_FILE}"
	for experiment in "${EXPERIMENTS[@]}"; do
                experiment_name=$(grep -o '"experiment_name": *"[^"]*"' ./experiments/${experiment}.json | sed 's/.*: *"\([^"]*\)"/\1/')
                echo "curl -X POST http://${KRUIZE_URL}/listRecommendations?experiment_name=${experiment_name}" | tee -a "${LOG_FILE}"
        done
	
	echo | tee -a "${LOG_FILE}"
  	echo "######################################################" | tee -a "${LOG_FILE}"
  	echo | tee -a "${LOG_FILE}"
}
