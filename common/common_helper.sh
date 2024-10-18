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
KIND_KUBERNETES_VERSION=v1.28.0
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
	cluster_name=$1
	echo "       ${cluster_name} resource config needed for demo:"
	echo "       CPUs=8, Memory=16384MB"
}

# Checks if the system which tries to run kruize is having minimum resources required
function sys_cpu_mem_check() {
	cluster_name=$1
	if [[ "$OSTYPE" == "linux"* ]]; then
    # Linux
    SYS_CPU=$(cat /proc/cpuinfo | grep "^processor" | wc -l)
    SYS_MEM=$(grep MemTotal /proc/meminfo | awk '{printf ("%.0f\n", $2/(1024))}')
	elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    SYS_CPU=$(sysctl -n hw.ncpu)
    SYS_MEM=$(sysctl -n hw.memsize | awk '{printf ("%.0f\n", $1/1024/1024)}')
	elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    # Windows
    SYS_CPU=$(powershell -Command "Get-WmiObject -Class Win32_Processor | Measure-Object -Property NumberOfCores -Sum | Select-Object -ExpandProperty Sum")
    SYS_MEM=$(powershell -Command "[math]::truncate((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1MB)")
	else
    echo "Unsupported OS: $OSTYPE"
    exit 1
	fi

	if [ "${SYS_CPU}" -lt "${MIN_CPU}" ]; then
		echo "CPU's on system : ${SYS_CPU} | Minimum CPU's required for demo : ${MIN_CPU}"
		print_min_resources ${cluster_name}
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
	repo_name=$1
	echo
	echo "#######################################"
	echo "1. Cloning ${repo_name} git repos"
	if [ ! -d ${repo_name} ]; then
		git clone git@github.com:kruize/${repo_name}.git >/dev/null 2>/dev/null
		if [ $? -ne 0 ]; then
			git clone https://github.com/kruize/${repo_name}.git 2>/dev/null
		fi
		check_err "ERROR: git clone of kruize/${repo_name} failed."
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
#   Kruize Install
###########################################
function kruize_install() {
	echo
	echo "#######################################"
	echo "6. Installing Kruize"
	if [ ! -d autotune ]; then
		echo "ERROR: autotune dir not found."
		if [[ ${autotune_restart} -eq 1 ]]; then
			echo "ERROR: Kruize not running. Wrong use of restart command"
		fi
		exit -1
	fi
	pushd autotune >/dev/null
		KRUIZE_VERSION="$(grep -A 1 "autotune" pom.xml | grep version | awk -F '>' '{ split($2, a, "<"); print a[1] }')"
		# Kruize UI repo
		KRUIZE_UI_REPO="quay.io/kruize/kruize-ui"
		# assign cluster_type to a temp variable in order to apply the correct yaml
		CLUSTER_TYPE_TEMP=${CLUSTER_TYPE}
		if [ ${CLUSTER_TYPE} == "kind" ]; then
			CLUSTER_TYPE_TEMP="minikube"
		fi

		echo "Terminating existing installation of kruize with  ./deploy.sh -c ${CLUSTER_TYPE_TEMP} -m ${target} -t"
		./deploy.sh -c ${CLUSTER_TYPE_TEMP} -m ${target} -t >/dev/null 2>/dev/null
		sleep 5
		if [ -z "${KRUIZE_DOCKER_IMAGE}" ]; then
			KRUIZE_DOCKER_IMAGE=${KRUIZE_DOCKER_REPO}:${KRUIZE_VERSION}
		fi
		DOCKER_IMAGES="-i ${KRUIZE_DOCKER_IMAGE}"
		if [ ! -z "${HPO_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -o ${KRUIZE_DOCKER_IMAGE}"
		fi
		if [ ! -z "${KRUIZE_UI_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -u ${KRUIZE_UI_DOCKER_IMAGE}"
		fi
		echo
		echo "Starting kruize installation with  ./deploy.sh -c ${CLUSTER_TYPE_TEMP} ${DOCKER_IMAGES} -m ${target}"
		echo

		./deploy.sh -c ${CLUSTER_TYPE_TEMP} ${DOCKER_IMAGES} -m ${target}
		check_err "ERROR: kruize failed to start, exiting"

		echo -n "Waiting 40 seconds for Kruize to sync with Prometheus..."
		sleep 40
		echo "done"
	popd >/dev/null
	echo "#######################################"
	echo
}

function kruize_uninstall() {
	echo
	echo "Uninstalling Kruize"
	echo
	if [ ! -d autotune ]; then
		return
	fi
	pushd autotune >/dev/null
		./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t
		sleep 10
		check_err "ERROR: Failed to terminate kruize"
		echo
	popd >/dev/null
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
#   Kind Start
###########################################
function kind_start() {
	echo
	echo "#######################################"
	echo "2. Deleting kind clusters, if any"
	kind delete clusters --all
	sleep 2
	echo "3. Starting new kind cluster"
	echo

	kind create cluster --image kindest/node:${KIND_KUBERNETES_VERSION}
	kubectl cluster-info --context kind-kind
	kubectl config use-context kind-kind
	check_err "ERROR: kind failed to start, exiting"
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
#   Kind Delete
###########################################
function kind_delete() {
	echo "2. Deleting kind cluster"
	kind delete clusters --all
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
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			./scripts/prometheus_on_minikube.sh -as
		else
			./scripts/prometheus_on_kind.sh -as
		fi
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
  	NAMESPACE="${1:-default}"
	BENCHMARK="${2:-tfb}"
	MANIFESTS="${3:-default_manifests}"

	echo
	echo "#######################################"
	pushd benchmarks >/dev/null
		if [ ${BENCHMARK} == "tfb" ]; then
			echo "5. Installing TechEmpower (Quarkus REST EASY) benchmark into cluster"
			pushd techempower >/dev/null
			# Reduce the requests to 1core-512Mi to accomodate the benchmark in resourcehub
			sed -i '/requests:/ {n; s/\(cpu: \)\([0-9]*\.[0-9]*\|\([0-9]*\)\)/\10.5/}' ./manifests/${MANIFESTS}/postgres.yaml
			sed -i '/requests:/ {n; n; s/\(memory: \)\"[^\"]*\"/\1\"512Mi\"/}' ./manifests/${MANIFESTS}/postgres.yaml
			sed -i '/requests:/ {n; s/\(cpu: \)\([0-9]*\.[0-9]*\|\([0-9]*\)\)/\11.5/}' ./manifests/${MANIFESTS}/quarkus-resteasy-hibernate.yaml
			sed -i '/requests:/ {n; n; s/\(memory: \)\"[^\"]*\"/\1\"512Mi\"/}' ./manifests/${MANIFESTS}/quarkus-resteasy-hibernate.yaml
			kubectl apply -f manifests/${MANIFESTS} -n ${NAMESPACE}
			check_err "ERROR: TechEmpower app failed to start, exiting"
			popd >/dev/null
		fi
		if [ ${BENCHMARK} == "human-eval" ]; then
			echo "#######################################"
			echo "Running HumanEval benchmark job in background"
			echo
			pushd human-eval-benchmark/manifests >/dev/null
				sed -i 's/namespace: kruize-hackathon/namespace: "'"${NAMESPACE}"'"/' pvc.yaml
				sed -i 's/namespace: kruize-hackathon/namespace: "'"${NAMESPACE}"'"/' job.yaml
				# Update num_prompts value to 150 to run the benchmark for atleast 15 mins
				sed -i "s/value: '10'/value: '150'/" job.yaml
				oc apply -f pvc.yaml -n ${NAMESPACE}
				oc apply -f job.yaml -n ${NAMESPACE}
				check_err "ERROR: Human eval job failed to start, exiting"
			popd >/dev/null
		fi
		if [ ${BENCHMARK} == "ttm" ]; then
			echo "#######################################"
			echo "Running Training TTM benchmark job in background"
			pushd AI-MLbenchmarks/ttm >/dev/null
				echo ""
                                ./run_ttm.sh ${NAMESPACE} >> ${LOG_FILE} &
                                check_err "ERROR: Training ttm jobs failed to start, exiting"
			popd >/dev/null
		fi
		if [ ${BENCHMARK} == "llm-rag" ]; then
			echo "#######################################"
			echo "Installing LLM-RAG benchmark into cluster"
			pushd AI-MLbenchmarks/llm-rag >/dev/null
				./deploy.sh ${NAMESPACE}
				check_err "ERROR: llm-rag benchmark failed to start, exiting"
			popd >/dev/null
		fi

	popd >/dev/null
	echo "#######################################"
	echo
}

###########################################
#   Benchmarks Uninstall
###########################################
function benchmarks_uninstall() {
        NAMESPACE="${1:-default}"
        MANIFESTS="${2:-default_manifests}"
	GPUS="${3:-0}"
        echo
        echo "#######################################"
        pushd benchmarks >/dev/null
                echo "Uninstalling TechEmpower (Quarkus REST EASY) benchmark in cluster"
                pushd techempower >/dev/null
                kubectl delete -f manifests/${MANIFESTS} -n ${NAMESPACE}
                check_err "ERROR: TechEmpower app failed to delete, exiting"
                popd >/dev/null

		if [ ${GPUS} > 0 ];then
			# Commenting for now
			# echo "Installing HumanEval benchmark job into cluster"
			# pushd AI-MLbenchmarks/human-eval >/dev/null
                        # ./cleanup.sh ${NAMESPACE}
                        # check_err "ERROR: Human eval job failed to delete, exiting"
			# popd >/dev/null

			echo "Installing Training TTM benchmark job into cluster"
			pushd AI-MLbenchmarks/ttm >/dev/null
			./cleanup.sh ${NAMESPACE}
			check_err "ERROR: Training ttm jobs failed to delete, exiting"
			popd >/dev/null

			echo "Installing LLM-RAG benchmark into cluster"
			pushd AI-MLbenchmarks/llm-rag >/dev/null
			./cleanup.sh ${NAMESPACE}
			check_err "ERROR: llm-rag benchmark failed to delete, exiting"
			popd >/dev/null
                fi

        popd >/dev/null
        echo "#######################################"
        echo
}

#
# Start a background load on the benchmark for 20 mins
#
function apply_benchmark_load() {
	TECHEMPOWER_LOAD_IMAGE="quay.io/kruizehub/tfb_hyperfoil_load:0.25.2"
	APP_NAMESPACE="${1:-default}"
	LOAD_DURATION="${2:-1200}"

	if kubectl get pods --namespace ${APP_NAMESPACE} -o jsonpath='{.items[*].metadata.name}' | grep -q "tfb"; then
		echo
		echo "################################################################################################################"
		echo " Starting ${LOAD_DURATION} secs background load against the techempower benchmark in ${APP_NAMESPACE} namespace "
		echo "################################################################################################################"
		echo
		if [ ${CLUSTER_TYPE} == "kind" ] || [ ${CLUSTER_TYPE} == "minikube" ]; then
			TECHEMPOWER_ROUTE=${TECHEMPOWER_URL}
		elif [ ${CLUSTER_TYPE} == "aks" ]; then
			TECHEMPOWER_ROUTE=${TECHEMPOWER_URL}
		elif [ ${CLUSTER_TYPE} == "openshift" ]; then
			TECHEMPOWER_ROUTE=$(oc get route -n ${APP_NAMESPACE} --template='{{range .items}}{{.spec.host}}{{"\n"}}{{end}}')
		fi
		# docker run -d --rm --network="host"  ${TECHEMPOWER_LOAD_IMAGE} /opt/run_hyperfoil_load.sh ${TECHEMPOWER_ROUTE} <END_POINT> <DURATION> <THREADS> <CONNECTIONS>
		docker run -d --rm --network="host"  ${TECHEMPOWER_LOAD_IMAGE} /opt/run_hyperfoil_load.sh ${TECHEMPOWER_ROUTE} queries?queries=20 ${LOAD_DURATION} 512 4096 #1024 8096
	fi

	if kubectl get pods --namespace testllm -o jsonpath='{.items[*].metadata.name}' | grep -q "llm"; then
		pushd benchmarks/AI-MLbenchmarks/llm-rag >/dev/null
		echo
                echo "################################################################################################################"
                echo " Starting background load against the llm-rag benchmark in ${APP_NAMESPACE} namespace "
                echo "################################################################################################################"
		./run_load.sh ${APP_NAMESPACE} >> ${LOG_FILE} &
		popd >/dev/null
	fi

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

###########################################
#   Check if minikube is installed
###########################################
function check_minikube() {
	if ! which minikube >/dev/null 2>/dev/null; then
		echo "ERROR: Please install minikube and try again"
		print_min_resources
		exit 1
	fi
}

###########################################
#   Deploy TFB Benchmarks - multiple import
###########################################
function create_namespace() {
	CAPP_NAMESPACE="${1:-test-multiple-import}"
	echo
	echo "#########################################"
	if kubectl get namespace "${CAPP_NAMESPACE}" &> /dev/null; then
		echo "Namespace ${CAPP_NAMESPACE} exists."
	else
		echo "Creating new namespace: ${CAPP_NAMESPACE}"
		kubectl create namespace ${CAPP_NAMESPACE}
	fi
	echo "#########################################"
	echo
}

###########################################
#   Check if kind is installed
###########################################
function check_kind() {
	if ! which kind >/dev/null 2>/dev/null; then
		echo "ERROR: Please install kind and try again"
		print_min_resources
		exit 1
	fi
}

###########################################
#   Delete namespace
###########################################
function delete_namespace() {
  DAPP_NAMESPACE=$1
  echo
  echo "#########################################"
  # Check if the namespace exists
    if kubectl get namespace "${DAPP_NAMESPACE}" > /dev/null 2>&1; then
      echo "Deleting namespace: ${DAPP_NAMESPACE}"
      kubectl delete namespace "${DAPP_NAMESPACE}"
    else
      echo "Namespace '${DAPP_NAMESPACE}' does not exist."
    fi
  echo "#########################################"
  echo
}

###########################################
#   Apply namespace resource quota
###########################################
function apply_namespace_resource_quota() {
	# Define the namespace and resource quota file path
	CAPP_NAMESPACE="${1:-default}"
	RESOURCE_QUOTA_FILE="${2:-namespace_resource_quota.yaml}"

	echo 
	echo "Updating namespace resource quota YAML"
	sed -i 's/namespace: default/namespace: "'"${CAPP_NAMESPACE}"'"/' "${RESOURCE_QUOTA_FILE}"
	echo
	echo "Applying namespace resource quota in namespace: ${CAPP_NAMESPACE}"
	
	# Apply the resource quota YAML to the namespace
	if kubectl apply -f "${RESOURCE_QUOTA_FILE}" -n "${CAPP_NAMESPACE}" &> /dev/null; then
		echo "Resource quota applied successfully."
	else
			echo "Failed to apply resource quota."
	fi

	echo "#########################################"
	echo
}

###########################################
#   Delete namespace resource quota
###########################################
function delete_namespace_resource_quota() {
	# Define the namespace and resource quota name
	CAPP_NAMESPACE="${1:-default}"
	RESOURCE_QUOTA_NAME="${2:-default-ns-quota}"

	echo
	echo "Deleting namespace resource quota: ${RESOURCE_QUOTA_NAME} in namespace: ${CAPP_NAMESPACE}"
	
	# Delete the resource quota in the namespace
	if kubectl delete resourcequota "${RESOURCE_QUOTA_NAME}" -n "${CAPP_NAMESPACE}" &> /dev/null; then
		echo "Namespace resource quota ${RESOURCE_QUOTA_NAME} deleted successfully."
	else
		echo "Failed to delete namespace resource quota. It may not exist or there was an error."
	fi

	echo "#########################################"
	echo
}

# Function to check if a port is in use
function is_port_in_use() {
  local port=$1
  if lsof -i :$port -t >/dev/null 2>&1; then
    return 0 # Port is in use
  else
    return 1 # Port is not in use
  fi
}


###########################################
#  Port forward the URLs
###########################################
function port_forward() {
	kubectl_cmd="kubectl -n monitoring"
	port_flag="false"

	# enable port forwarding to access the endpoints since 'Kind' doesn't expose external IPs
	# Start port forwarding for kruize service in the background
	if is_port_in_use ${KRUIZE_PORT}; then
		echo "Error: Port ${KRUIZE_PORT} is already in use. Port forwarding for kruize service cannot be established."
		port_flag="true"
	else
		${kubectl_cmd} port-forward svc/kruize ${KRUIZE_PORT}:8080 > /dev/null 2>&1 &
	fi
	# Start port forwarding for kruize-ui-nginx-service in the background
	if is_port_in_use ${KRUIZE_UI_PORT}; then
		echo "Error: Port ${KRUIZE_UI_PORT} is already in use. Port forwarding for kruize-ui-nginx-service cannot be established."
		port_flag="true"
	else
		${kubectl_cmd} port-forward svc/kruize-ui-nginx-service ${KRUIZE_UI_PORT}:8080 > /dev/null 2>&1 &
	fi
	# Start port forwarding for tfb-service in the background
	if is_port_in_use ${TECHEMPOWER_PORT}; then
		echo "Error: Port ${TECHEMPOWER_PORT} is already in use. Port forwarding for tfb-service cannot be established."
		port_flag="true"
	else
		kubectl port-forward svc/tfb-qrh-service ${TECHEMPOWER_PORT}:8080 > /dev/null 2>&1 &
	fi

	if ${port_flag} = "true"; then
		echo "Exiting..."
		exit 1
	fi
}

#
# "local" flag is turned off by default for now. This needs to be set to true.
#
function kruize_local_patch() {
	CRC_DIR="./manifests/crc/default-db-included-installation"
	KRUIZE_CRC_DEPLOY_MANIFEST_OPENSHIFT="${CRC_DIR}/openshift/kruize-crc-openshift.yaml"
	KRUIZE_CRC_DEPLOY_MANIFEST_MINIKUBE="${CRC_DIR}/minikube/kruize-crc-minikube.yaml"
	KRUIZE_CRC_DEPLOY_MANIFEST_AKS="${CRC_DIR}/aks/kruize-crc-aks.yaml"

	pushd autotune >/dev/null
		# Checkout mvp_demo to get the latest mvp_demo release version
		git checkout mvp_demo >/dev/null 2>/dev/null

		if [ ${CLUSTER_TYPE} == "kind" ]; then
			sed -i 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_MINIKUBE}
		elif [ ${CLUSTER_TYPE} == "openshift" ]; then
			sed -i 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_OPENSHIFT}
		elif [ ${CLUSTER_TYPE} == "aks" ]; then
                        perl -pi -e 's/"local": "false"/"local": "true"/' ${KRUIZE_CRC_DEPLOY_MANIFEST_AKS}
		fi
	popd >/dev/null
}


###########################################
#  Get URLs
###########################################
function get_urls() {
  	APP_NAMESPACE="${1:-default}"
	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		kubectl_cmd="kubectl -n monitoring"
		kubectl_app_cmd="kubectl -n ${APP_NAMESPACE}"

		MINIKUBE_IP=$(minikube ip)

		KRUIZE_PORT=$(${kubectl_cmd} get svc kruize --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
		KRUIZE_UI_PORT=$(${kubectl_cmd} get svc kruize-ui-nginx-service --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)

		if [ ${demo} == "local" ]; then
			TECHEMPOWER_PORT=$(${kubectl_app_cmd} get svc tfb-qrh-service --no-headers -o=custom-columns=PORT:.spec.ports[*].nodePort)
			TECHEMPOWER_IP=$(${kubectl_app_cmd} get pods -l=app=tfb-qrh-deployment -o wide -o=custom-columns=NODE:.spec.nodeName --no-headers)
		fi

		export KRUIZE_URL="${MINIKUBE_IP}:${KRUIZE_PORT}"
		export KRUIZE_UI_URL="${MINIKUBE_IP}:${KRUIZE_UI_PORT}"
		export TECHEMPOWER_URL="${MINIKUBE_IP}:${TECHEMPOWER_PORT}"

	elif [ "${CLUSTER_TYPE}" == "aks" ]; then
		kubectl_cmd="kubectl -n monitoring"

		# Expose kruize/kruize-ui-nginx-service via LoadBalancer
		KRUIZE_SERVICE_URL=$(${kubectl_cmd} get svc kruize -o custom-columns=EXTERNAL-IP:.status.loadBalancer.ingress[*].ip --no-headers)
		KRUIZE_UI_SERVICE_URL=$(${kubectl_cmd} get svc kruize-ui-nginx-service -o custom-columns=EXTERNAL-IP:.status.loadBalancer.ingress[*].ip --no-headers)

		export KRUIZE_URL="${KRUIZE_SERVICE_URL}:8080"
		export KRUIZE_UI_URL="${KRUIZE_UI_SERVICE_URL}:8080"

		
		if [ ${demo} == "local" ]; then
			unset TECHEMPOWER_IP
			export TECHEMPOWER_IP=$(kubectl -n default get svc tfb-qrh-service -o custom-columns=EXTERNAL-IP:.status.loadBalancer.ingress[*].ip --no-headers)
			export TECHEMPOWER_URL="${TECHEMPOWER_IP}:8080"
		fi
	
	elif [ ${CLUSTER_TYPE} == "kind" ]; then
		export KRUIZE_URL="${KIND_IP}:${KRUIZE_PORT}"
		export KRUIZE_UI_URL="${KIND_IP}:${KRUIZE_UI_PORT}"

		if [ ${demo} == "local" ]; then
			export TECHEMPOWER_URL="${KIND_IP}:${TECHEMPOWER_PORT}"
		fi

	elif [ ${CLUSTER_TYPE} == "openshift" ]; then
		kubectl_cmd="oc -n openshift-tuning"
		kubectl_app_cmd="oc -n ${APP_NAMESPACE}"

		${kubectl_cmd} expose service kruize
		${kubectl_cmd} expose service kruize-ui-nginx-service
		${kubectl_cmd} annotate route kruize --overwrite haproxy.router.openshift.io/timeout=60s

		if [ ${demo} == "local" ]; then
			${kubectl_app_cmd} expose service tfb-qrh-service
			export TECHEMPOWER_URL=$(${kubectl_app_cmd} get route tfb-qrh-service --no-headers -o wide -o=custom-columns=NODE:.spec.host)
		fi

		export KRUIZE_URL=$(${kubectl_cmd} get route kruize --no-headers -o wide -o=custom-columns=NODE:.spec.host)
		export KRUIZE_UI_URL=$(${kubectl_cmd} get route kruize-ui-nginx-service --no-headers -o wide -o=custom-columns=NODE:.spec.host)
	fi
}

###########################################
#  Show URLs
###########################################
function show_urls() {
	if [ ${demo} == "local" ]; then
		{
		echo
		echo "#######################################"
		echo "#             Quarkus App             #"
		echo "#######################################"
		echo "Info: Access techempower app at http://${TECHEMPOWER_URL}/db"
		echo "Info: Access techempower app metrics at http://${TECHEMPOWER_URL}/q/metrics"
		} >> "${LOG_FILE}" 2>&1
	fi

	echo
	echo "#######################################"
	echo "#              Kruize               #"
	echo "#######################################"
	echo "Info: Access kruize UI at http://${KRUIZE_UI_URL}"
	echo "Info: List all Kruize Experiments at http://${KRUIZE_URL}/listExperiments"
	echo
}

function setup_workload() {
	export ns_name="tfb"
	export count=3

	for ((loop=1; loop<=${count}; loop++));
	do
		create_namespace ${ns_name}-${loop}
		sleep 5
		benchmarks_install ${ns_name}-${loop}
	done

	if [ ${CLUSTER_TYPE} == "openshift" ]; then
		for ((loop=1; loop<=${count}; loop++));
		do
			oc expose svc/tfb-qrh-service -n ${ns_name}-${loop}
			oc get route -n ${ns_name}-${loop}
		done
	fi

	for ((loop=1; loop<=${count}; loop++));
	do
		apply_benchmark_load ${ns_name}-${loop}
	done
}

#
#
#
function kruize_local_demo_setup() {
	bench=$1
	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#       Kruize Local Demo Setup       #"
	echo "#######################################"
	echo

	{

	if [ ${kruize_restart} -eq 0 ]; then
		clone_repos autotune
		clone_repos benchmarks
		if [ ${CLUSTER_TYPE} == "minikube" ]; then
			sys_cpu_mem_check
			check_minikube
			minikube >/dev/null
			check_err "ERROR: minikube not installed"
			minikube_start
			prometheus_install autotune
		elif [ ${CLUSTER_TYPE} == "kind" ]; then
			check_kind
			kind >/dev/null
			check_err "ERROR: kind not installed"
			kind_start
			prometheus_install
		fi
		if [ ${demo} == "local" ]; then
			create_namespace ${APP_NAMESPACE}
			if [ ${#EXPERIMENTS[@]} -ne 0 ]; then
				benchmarks_install ${APP_NAMESPACE} ${bench}
			fi
			echo ""
		elif [ ${demo} == "bulk" ]; then
			setup_workload
		fi
	fi
	kruize_local_patch
	kruize_install
	echo
	# port forward the urls in case of kind
	if [ ${CLUSTER_TYPE} == "kind" ]; then
		port_forward
	fi

	get_urls

	} >> "${LOG_FILE}" 2>&1

	if [ ${demo} == "local" ]; then
		kruize_local
		if [ ${#EXPERIMENTS[@]} -ne 0 ]; then
			kruize_local_experiments
		fi
		show_urls
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
			echo "#######################################"
			echo "#     Apply the benchmark load        #"
			echo "#######################################"
			echo
			apply_benchmark_load ${APP_NAMESPACE} ${LOAD_DURATION}
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


function kruize_local_demo_terminate() {
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#       Kruize Demo Terminate       #"
	echo "#######################################"
	echo
	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube_delete
	elif [ ${CLUSTER_TYPE} == "kind" ]; then
		kind_delete
	else
		kruize_uninstall
	fi
	if [ ${demo} == "local" ]; then
		delete_namespace "test-multiple-import"
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
	delete_repos autotune
	delete_repos "benchmarks"
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Kruize demo cleanup took ${elapsed_time} seconds"
	echo
}

function kruize_local_disable() {
        if [ ${CLUSTER_TYPE} == "minikube" ]; then
                sed -i 's/"local": "true"/"local": "false"/' manifests/crc/default-db-included-installation/minikube/kruize-crc-minikube.yaml
        elif [ ${CLUSTER_TYPE} == "openshift" ]; then
                sed -i 's/"local": "true"/"local": "false"/' manifests/crc/default-db-included-installation/openshift/kruize-crc-openshift.yaml
        fi
}

