"""
Cluster management for Kruize Demos v2
"""
import time
import subprocess
from typing import Optional, Dict, Any, List
from pathlib import Path

from .utils import run_command, check_cluster_running, wait_for_pod_ready
from .logger import get_logger


class ClusterManager:
    """Manage Kubernetes cluster operations"""
    
    def __init__(self, cluster_type: str = "kind", namespace: str = "monitoring", cluster_name: str = "kruize-demo"):
        """
        Initialize cluster manager
        
        Args:
            cluster_type: Type of cluster (kind, minikube, openshift)
            namespace: Default namespace
            cluster_name: Name of the cluster (used for kind)
        """
        self.cluster_type = cluster_type
        self.namespace = namespace
        self.cluster_name = cluster_name
        self.logger = get_logger()
    
    def is_running(self) -> bool:
        """
        Check if cluster is running and kubectl is properly configured
        
        Returns:
            True if running and accessible, False otherwise
        """
        return check_cluster_running(self.cluster_type, self.cluster_name)
    
    def setup_minikube(
        self,
        cpus: int = 8,
        memory: int = 16384,
        driver: Optional[str] = None
    ) -> bool:
        """
        Setup Minikube cluster
        
        Args:
            cpus: Number of CPUs
            memory: Memory in MB
            driver: Driver to use (docker, podman, etc.)
            
        Returns:
            True if successful
        """
        try:
            self.logger.info("Setting up Minikube cluster...")
            
            # Delete existing cluster
            self.logger.debug("Deleting existing Minikube cluster if any...")
            run_command(['minikube', 'delete'], check=False, capture_output=True)
            
            # Start new cluster
            cmd = [
                'minikube', 'start',
                f'--cpus={cpus}',
                f'--memory={memory}'
            ]
            
            if driver:
                cmd.append(f'--driver={driver}')
            
            self.logger.debug(f"Starting Minikube: {' '.join(cmd)}")
            run_command(cmd, timeout=600)
            
            self.logger.success("Minikube cluster started successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to setup Minikube: {e}")
            return False
    
    def setup_kind(self, cluster_name: Optional[str] = None) -> bool:
        """
        Setup Kind cluster - creates a fresh cluster
        
        Args:
            cluster_name: Name of the cluster
            
        Returns:
            True if successful
        """
        # Use instance cluster_name if not provided
        if cluster_name is None:
            cluster_name = self.cluster_name
            
        try:
            self.logger.info("Setting up fresh Kind cluster...")
            
            # Delete existing cluster with the same name (if any)
            self.logger.debug(f"Deleting existing Kind cluster '{cluster_name}' if any...")
            run_command(['kind', 'delete', 'cluster', '--name', cluster_name],
                       check=False, capture_output=True)
            
            # Create cluster config
            config = """kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 8080
    hostPort: 8080
    protocol: TCP
  - containerPort: 8081
    hostPort: 8081
    protocol: TCP
  - containerPort: 9090
    hostPort: 9090
    protocol: TCP
"""
            
            config_file = Path('/tmp/kind-config.yaml')
            config_file.write_text(config)
            
            # Create cluster
            self.logger.debug(f"Creating Kind cluster: {cluster_name}")
            run_command([
                'kind', 'create', 'cluster',
                '--name', cluster_name,
                '--config', str(config_file)
            ], timeout=600)
            
            # Verify kubectl context was set
            self.logger.debug("Verifying kubectl context...")
            context_result = run_command(['kubectl', 'config', 'current-context'],
                                       capture_output=True, timeout=30)
            current_context = context_result.stdout.strip()
            self.logger.debug(f"Current kubectl context: {current_context}")
            
            if current_context != f'kind-{cluster_name}':
                self.logger.warning(f"Context mismatch. Setting to kind-{cluster_name}")
                run_command(['kubectl', 'config', 'use-context', f'kind-{cluster_name}'],
                          timeout=30)
            
            self.logger.success("Kind cluster created successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to setup Kind: {e}")
            return False
    
    def install_prometheus(self) -> bool:
        """
        Install Prometheus (Python implementation following bash script flow)
        
        Returns:
            True if successful
            
        Note:
            Follows prometheus_on_kind.sh logic but implemented in Python
        """
        try:
            self.logger.info("Installing Prometheus...")
            self.logger.info("⏳ This may take 2-3 minutes. Check kruize-demo.log for detailed progress.")
            
            # For Kind/Minikube, install prometheus
            if self.cluster_type in ['kind', 'minikube']:
                prometheus_ns = "monitoring"
                
                # Check if prometheus is already running
                self.logger.debug("Checking if Prometheus is already installed...")
                try:
                    result = run_command([
                        'kubectl', 'get', 'pods', '-n', prometheus_ns,
                        '-l', 'app.kubernetes.io/name=prometheus'
                    ], capture_output=True, check=False, timeout=30)
                    
                    if result.returncode == 0 and 'prometheus-k8s-1' in result.stdout:
                        self.logger.success("✅ Prometheus is already installed and running")
                        return True
                except:
                    pass
                
                # Create cloned_repos directory
                cloned_repos_dir = Path.cwd() / 'cloned_repos'
                cloned_repos_dir.mkdir(exist_ok=True)
                
                import time
                
                # Install cadvisor
                self.logger.info("📦 Installing cadvisor...")
                cadvisor_dir = cloned_repos_dir / 'cadvisor'
                if not cadvisor_dir.exists():
                    self.logger.debug("Cloning cadvisor repository...")
                    run_command([
                        'git', 'clone',
                        'https://github.com/google/cadvisor.git',
                        str(cadvisor_dir)
                    ], timeout=120)
                
                cadvisor_base = cadvisor_dir / 'deploy' / 'kubernetes' / 'base'
                self.logger.debug("Applying cadvisor manifests...")
                run_command([
                    'kubectl', 'apply', '-k', str(cadvisor_base)
                ], timeout=120)
                
                # Install kube-prometheus
                self.logger.info("📦 Installing Prometheus stack...")
                prom_tag = "v0.13.0"
                kube_prom_dir = cloned_repos_dir / 'kube-prometheus'
                
                if not kube_prom_dir.exists():
                    self.logger.debug(f"Cloning kube-prometheus repository (tag: {prom_tag})...")
                    run_command([
                        'git', 'clone', '-b', prom_tag,
                        'https://github.com/coreos/kube-prometheus.git',
                        str(kube_prom_dir)
                    ], timeout=120)
                
                prom_manifests = kube_prom_dir / 'manifests'
                
                # Apply setup manifests
                self.logger.debug("Creating Prometheus CRDs and namespace...")
                run_command([
                    'kubectl', 'apply', '--server-side',
                    '-f', str(prom_manifests / 'setup')
                ], timeout=120)
                
                # Apply remaining manifests
                self.logger.debug("Applying Prometheus manifests...")
                run_command([
                    'kubectl', 'apply', '--server-side',
                    '-f', str(prom_manifests)
                ], timeout=180)
                
                # Wait for prometheus pods to spawn
                self.logger.debug("Waiting for Prometheus pods to spawn...")
                max_wait = 60
                elapsed = 0
                while elapsed < max_wait:
                    result = run_command([
                        'kubectl', 'get', 'pods', '-n', prometheus_ns
                    ], capture_output=True, check=False, timeout=10)
                    
                    if 'prometheus-k8s-1' in result.stdout:
                        break
                    time.sleep(5)
                    elapsed += 5
                
                # Wait for prometheus to be ready
                from .utils import wait_for_pods_ready
                self.logger.debug("Waiting for Prometheus to be ready...")
                if wait_for_pods_ready(prometheus_ns, 'app.kubernetes.io/name=prometheus', timeout=180):
                    self.logger.success("✅ Prometheus installed successfully")
                else:
                    self.logger.warning("⚠️  Prometheus pods not fully ready, but continuing...")
                
                time.sleep(2)
                    
            else:
                # OpenShift already has Prometheus
                self.logger.info("✅ OpenShift cluster detected - Prometheus should be pre-installed")
            
            return True
            
        except subprocess.TimeoutExpired:
            self.logger.error("❌ Command timed out during Prometheus installation")
            self.logger.warning("⚠️  Continuing without Prometheus - some features may not work")
            self.logger.info("💡 Check kruize-demo.log for detailed error information")
            return True  # Don't fail the entire demo
        except subprocess.CalledProcessError as e:
            self.logger.error(f"❌ Failed to install Prometheus: {e}")
            self.logger.warning("⚠️  Continuing without Prometheus - some features may not work")
            self.logger.info("💡 Check kruize-demo.log for detailed error information")
            return True  # Don't fail the entire demo
        except Exception as e:
            self.logger.error(f"❌ Unexpected error during Prometheus installation: {e}")
            self.logger.warning("⚠️  Continuing without Prometheus")
            self.logger.info("💡 Check kruize-demo.log for detailed error information")
            return True
    
    def create_namespace(self, namespace: str) -> bool:
        """
        Create namespace if it doesn't exist
        
        Args:
            namespace: Namespace name
            
        Returns:
            True if successful
        """
        try:
            self.logger.debug(f"Checking if namespace '{namespace}' exists...")
            
            # Check if namespace exists with timeout
            result = run_command(
                ['kubectl', 'get', 'namespace', namespace],
                check=False,
                capture_output=True,
                timeout=30  # Add 30 second timeout
            )
            
            if result.returncode != 0:
                self.logger.info(f"📁 Creating namespace '{namespace}'...")
                run_command(
                    ['kubectl', 'create', 'namespace', namespace],
                    timeout=30
                )
                self.logger.success(f"✅ Namespace '{namespace}' created")
            else:
                self.logger.debug(f"Namespace '{namespace}' already exists")
            
            return True
            
        except subprocess.TimeoutExpired:
            self.logger.error(f"❌ Timeout while checking/creating namespace '{namespace}'")
            self.logger.warning("⚠️  kubectl command timed out. Check if cluster is responsive.")
            return False
        except subprocess.CalledProcessError as e:
            self.logger.error(f"❌ Failed to create namespace: {e}")
            return False
        except Exception as e:
            self.logger.error(f"❌ Unexpected error creating namespace: {e}")
            return False
    
    def get_service_url(self, service_name: str, namespace: str) -> Optional[str]:
        """
        Get service URL
        
        Args:
            service_name: Service name
            namespace: Namespace
            
        Returns:
            Service URL or None
        """
        try:
            if self.cluster_type == "minikube":
                # Get NodePort
                result = run_command([
                    'kubectl', '-n', namespace,
                    'get', 'svc', service_name,
                    '--no-headers',
                    '-o=custom-columns=PORT:.spec.ports[*].nodePort'
                ], capture_output=True)
                
                port = result.stdout.strip()
                
                # Get Minikube IP
                result = run_command(['minikube', 'ip'], capture_output=True)
                ip = result.stdout.strip()
                
                return f"http://{ip}:{port}"
                
            elif self.cluster_type == "kind":
                # Kind uses localhost with port forwarding
                return f"http://127.0.0.1:8080"
                
            elif self.cluster_type == "openshift":
                # Expose route and get URL
                run_command([
                    'oc', 'expose', f'svc/{service_name}',
                    '-n', namespace
                ], check=False, capture_output=True)
                
                result = run_command([
                    'oc', 'get', 'route', service_name,
                    '-n', namespace,
                    '-o', 'jsonpath={.spec.host}'
                ], capture_output=True)
                
                host = result.stdout.strip()
                return f"http://{host}"
            
            return None
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to get service URL: {e}")
            return None
    
    def port_forward(
        self,
        resource: str,
        namespace: str,
        local_port: int,
        remote_port: int
    ) -> Optional[subprocess.Popen]:
        """
        Setup port forwarding
        
        Args:
            resource: Resource (pod/service name)
            namespace: Namespace
            local_port: Local port
            remote_port: Remote port
            
        Returns:
            Popen process or None
        """
        try:
            self.logger.debug(f"Setting up port forward: {local_port} -> {resource}:{remote_port}")
            
            # Kill existing port forward
            self._kill_port_forward(namespace, resource)
            
            # Start new port forward
            process = subprocess.Popen(
                [
                    'kubectl', '-n', namespace,
                    'port-forward', resource,
                    f'{local_port}:{remote_port}'
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            
            # Wait a bit for port forward to establish
            time.sleep(5)
            
            return process
            
        except Exception as e:
            self.logger.error(f"Failed to setup port forward: {e}")
            return None
    
    def kill_service_port_forward(self, service_name: str) -> None:
        """
        Kill existing port forward processes for a specific service
        
        Args:
            service_name: Service name to kill port-forward for
        """
        try:
            # Find PIDs of port-forward processes for the specific service
            result = run_command(
                ['ps', 'aux'],
                check=False,
                capture_output=True
            )
            
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                for line in lines:
                    if 'kubectl' in line and 'port-forward' in line and f'svc/{service_name}' in line:
                        # Extract PID (second column)
                        parts = line.split()
                        if len(parts) > 1:
                            pid = parts[1]
                            self.logger.debug(f"Killing port-forward for {service_name} (PID: {pid})")
                            run_command(['kill', pid], check=False, capture_output=True)
                
                # Wait a bit for processes to die
                import time
                time.sleep(1)
        except Exception as e:
            self.logger.debug(f"Error killing port-forward for {service_name}: {e}")
    
    def check_ports_in_use(self, ports: list = [8080, 8081]) -> dict:
        """
        Check which processes are using specified ports
        
        Args:
            ports: List of ports to check
            
        Returns:
            Dictionary mapping port to process info (only kubectl port-forward processes)
        """
        port_info = {}
        try:
            for port in ports:
                # Use lsof to check what's using the port
                result = run_command(
                    ['lsof', '-i', f':{port}', '-sTCP:LISTEN'],
                    check=False,
                    capture_output=True
                )
                
                if result.returncode == 0 and result.stdout.strip():
                    lines = result.stdout.strip().split('\n')
                    if len(lines) > 1:  # Skip header
                        # Parse the output to get process info
                        process_line = lines[1]
                        parts = process_line.split()
                        if len(parts) >= 2:
                            process_name = parts[0]
                            pid = parts[1]
                            
                            # Only track kubectl port-forward processes, not cluster infrastructure
                            # gvproxy is part of Kind/Podman networking and should NOT be killed
                            if process_name == 'kubectl':
                                port_info[port] = {
                                    'process': process_name,
                                    'pid': pid,
                                    'line': process_line
                                }
                                self.logger.debug(f"Port {port} is in use by {process_name} (PID: {pid})")
                            else:
                                self.logger.debug(f"Port {port} is in use by {process_name} (cluster infrastructure, will not kill)")
        except Exception as e:
            self.logger.debug(f"Error checking ports: {e}")
        
        return port_info
    
    def kill_processes_on_ports(self, ports: list = [8080, 8081]) -> bool:
        """
        Kill processes using specified ports
        
        Args:
            ports: List of ports to free up
            
        Returns:
            True if successful
        """
        try:
            port_info = self.check_ports_in_use(ports)
            
            if not port_info:
                self.logger.debug(f"No processes found on ports {ports}")
                return True
            
            for port, info in port_info.items():
                pid = info['pid']
                process = info['process']
                self.logger.info(f"Killing process {process} (PID: {pid}) on port {port}")
                run_command(['kill', '-9', pid], check=False, capture_output=True)
            
            # Wait for processes to die
            import time
            time.sleep(2)
            
            # Verify ports are free
            remaining = self.check_ports_in_use(ports)
            if remaining:
                self.logger.warning(f"⚠️  Some ports still in use: {list(remaining.keys())}")
                return False
            
            self.logger.success(f"✅ Freed up ports: {ports}")
            return True
            
        except Exception as e:
            self.logger.error(f"Error killing processes on ports: {e}")
            return False
    
    def _kill_port_forward(self, namespace: str, resource: str):
        """Kill existing port forward processes (legacy method)"""
        # Extract service name from resource
        service_name = resource.replace('service/', '')
        self.kill_service_port_forward(service_name)
    
    def apply_manifest(self, manifest_file: str) -> bool:
        """
        Apply Kubernetes manifest
        
        Args:
            manifest_file: Path to manifest file
            
        Returns:
            True if successful
        """
        try:
            self.logger.debug(f"Applying manifest: {manifest_file}")
            run_command(['kubectl', 'apply', '-f', manifest_file])
            return True
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to apply manifest: {e}")
            return False
    
    def delete_manifest(self, manifest_file: str) -> bool:
        """
        Delete Kubernetes manifest
        
        Args:
            manifest_file: Path to manifest file
            
        Returns:
            True if successful
        """
        try:
            self.logger.debug(f"Deleting manifest: {manifest_file}")
            run_command(['kubectl', 'delete', '-f', manifest_file], check=False)
            return True
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to delete manifest: {e}")
            return False
    
    def check_and_cleanup_kruize(self, namespace: str) -> bool:
        """
        Check for existing Kruize deployments and clean them up
        Following bash script logic from lines 449-524
        
        Args:
            namespace: Namespace to check
            
        Returns:
            True if cleanup successful or nothing to cleanup
        """
        try:
            self.logger.debug("Checking for existing Kruize deployments...")
            
            # Check if cluster is accessible
            cluster_accessible = False
            try:
                result = run_command(
                    ['kubectl', 'cluster-info'],
                    capture_output=True,
                    check=False,
                    timeout=5
                )
                cluster_accessible = result.returncode == 0
            except:
                pass
            
            if not cluster_accessible:
                self.logger.debug("Cluster not accessible, skipping cleanup")
                return True
            
            # Check for existing deployments
            operator_exists = False
            kruize_exists = False
            
            # Check for operator deployment
            result = run_command(
                ['kubectl', 'get', 'deployment', 'kruize-operator', '-n', namespace],
                capture_output=True,
                check=False,
                timeout=10
            )
            operator_exists = result.returncode == 0
            
            # Check for kruize pods
            result = run_command(
                ['kubectl', 'get', 'pod', '-l', 'app=kruize', '-n', namespace],
                capture_output=True,
                check=False,
                timeout=10
            )
            kruize_exists = result.returncode == 0 and 'kruize' in result.stdout
            
            # If any exist, cleanup
            if operator_exists or kruize_exists:
                self.logger.info("🧹 Found existing Kruize deployment, cleaning up...")
                
                # Kill existing port-forwards (only for kind)
                if self.cluster_type == 'kind':
                    self.kill_service_port_forward('kruize')
                    self.kill_service_port_forward('kruize-ui-nginx-service')
                
                # Uninstall kruize
                if kruize_exists:
                    self.logger.debug("Uninstalling existing Kruize...")
                    run_command(
                        ['kubectl', 'delete', 'all', '-l', 'app=kruize', '-n', namespace],
                        check=False,
                        capture_output=True,
                        timeout=60
                    )
                    run_command(
                        ['kubectl', 'delete', 'all', '-l', 'app=kruize-ui-nginx', '-n', namespace],
                        check=False,
                        capture_output=True,
                        timeout=60
                    )
                    run_command(
                        ['kubectl', 'delete', 'all', '-l', 'app=kruize-db', '-n', namespace],
                        check=False,
                        capture_output=True,
                        timeout=60
                    )
                
                # Wait for cleanup to complete
                self.logger.debug("Waiting for cleanup to complete...")
                time.sleep(10)
                
                self.logger.success("✅ Cleanup complete")
            else:
                self.logger.debug("No existing Kruize deployment found")
            
            return True
            
        except Exception as e:
            self.logger.warning(f"⚠️  Error during cleanup check: {e}")
            return True  # Don't fail the demo
    
    def cleanup(self) -> bool:
        """
        Cleanup cluster
        
        Returns:
            True if successful
        """
        try:
            self.logger.info(f"Cleaning up {self.cluster_type} cluster...")
            
            if self.cluster_type == "minikube":
                run_command(['minikube', 'delete'], check=False)
            elif self.cluster_type == "kind":
                run_command(['kind', 'delete', 'cluster'], check=False)
            
            self.logger.success("Cluster cleanup completed")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to cleanup cluster: {e}")
            return False

# Made with Bob
