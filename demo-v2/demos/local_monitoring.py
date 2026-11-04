"""
Local Monitoring Demo Implementation
"""
from typing import Optional
from .base_demo import BaseDemo
from core.config import Config


class LocalMonitoringDemo(BaseDemo):
    """Local monitoring demo with live cluster workloads"""
    
    def __init__(self, config: Config):
        """Initialize local monitoring demo"""
        super().__init__(config)
        self.demo_name = "Local Monitoring"
    
    def run(self) -> bool:
        """
        Run local monitoring demo
        
        Returns:
            True if successful
        """
        self.start_timer()
        self.logger.print_header(f"Starting {self.demo_name} Demo")
        
        try:
            # Step 1: Setup cluster
            self.logger.print_section("Step 1: Cluster Setup")
            if not self.setup_cluster():
                return False
            
            # Step 2: Check and cleanup existing Kruize
            namespace = self.config.get_namespace(self.config.cluster.type)
            if not self.cluster_manager.check_and_cleanup_kruize(namespace):
                self.logger.print_warning("Cleanup check failed, continuing...")
            
            # Step 3: Install Prometheus (if needed)
            if self.config.cluster.type in ['kind', 'minikube']:
                self.logger.print_section("Step 3: Installing Prometheus")
                if not self.cluster_manager.install_prometheus():
                    self.logger.print_warning("Prometheus installation failed, continuing...")
            
            # Step 4: Deploy benchmarks (BEFORE Kruize - following bash script lines 559-587)
            if self.config.demo.deploy_benchmark:
                self.logger.print_section("Step 4: Deploying Benchmarks")
                if not self._deploy_benchmarks():
                    self.logger.print_warning("Benchmark deployment failed, continuing...")
                
                # Apply benchmark load if requested (following bash script lines 357-362)
                if getattr(self.config.demo, 'run_load', False):
                    self.logger.print_section("Step 4b: Applying Benchmark Load")
                    if not self._apply_benchmark_load():
                        self.logger.print_warning("Benchmark load failed, continuing...")
            
            # Step 5: Deploy Kruize (following bash script lines 605-639)
            self.logger.print_section("Step 5: Deploying Kruize")
            kruize_url = self._deploy_kruize()
            if not kruize_url:
                return False
            
            # Step 6: Setup Kruize client
            self.logger.print_section("Step 6: Connecting to Kruize")
            if not self.setup_kruize_client(kruize_url):
                return False
            
            # Step 7: Install metric and metadata profiles (following bash script lines 650-658)
            self.logger.print_section("Step 7: Installing Profiles")
            if not self._install_profiles():
                self.logger.print_warning("Profile installation failed, continuing...")
            
            # Step 8: Create experiments (following bash script lines 681-685)
            self.logger.print_section("Step 8: Creating Experiments")
            if not self._create_experiments():
                return False
            
            # Step 9: Generate recommendations (following bash script lines 222-277)
            self.logger.print_section("Step 9: Generating Recommendations")
            if not self._generate_recommendations():
                return False
            
            self.stop_timer()
            self.print_summary(True, "Local monitoring demo completed successfully!")
            
            # Print next steps
            self._print_next_steps(kruize_url)
            
            return True
            
        except Exception as e:
            self.logger.error(f"Demo failed: {e}")
            self.stop_timer()
            self.print_summary(False, str(e))
            return False
    
    def _deploy_kruize(self) -> Optional[str]:
        """
        Deploy Kruize service (Python implementation following bash script flow)
        
        Returns:
            Kruize URL if successful, None otherwise
        """
        import subprocess
        import time
        from pathlib import Path
        from core.utils import run_command, wait_for_pods_ready, clone_repo
        
        try:
            self.logger.info("Deploying Kruize...")
            
            # Ensure cluster manager is initialized
            if not self.cluster_manager:
                self.logger.error("❌ Cluster manager not initialized")
                return None
            
            # Check and free up ports 8080 and 8081 if needed (for kind clusters)
            if self.config.cluster.type == 'kind':
                self.logger.debug("Checking for kubectl port-forward processes on ports 8080 and 8081...")
                port_info = self.cluster_manager.check_ports_in_use([8080, 8081])
                if port_info:
                    self.logger.info("Found kubectl port-forward processes using required ports:")
                    for port, info in port_info.items():
                        self.logger.info(f"  Port {port}: {info['process']} (PID: {info['pid']})")
                    
                    self.logger.info("Cleaning up old port-forward processes...")
                    self.cluster_manager.kill_processes_on_ports([8080, 8081])
                else:
                    self.logger.debug("No kubectl port-forward processes found on ports 8080 and 8081")
            
            # Get namespace based on cluster type
            namespace = self.config.get_namespace(self.config.cluster.type)
            
            # Clone autotune repo if not present
            cloned_repos_dir = Path.cwd() / 'cloned_repos'
            cloned_repos_dir.mkdir(exist_ok=True)
            
            autotune_dir = cloned_repos_dir / 'autotune'
            if not autotune_dir.exists():
                self.logger.debug("Cloning autotune repository...")
                # Use direct HTTPS URL to avoid SSH issues
                run_command([
                    'git', 'clone',
                    'https://github.com/kruize/autotune.git',
                    str(autotune_dir)
                ], timeout=120)
            
            # Create namespace
            self.logger.debug(f"Creating namespace '{namespace}'...")
            if not self.cluster_manager.create_namespace(namespace):
                self.logger.warning(f"⚠️  Namespace '{namespace}' may already exist, continuing...")
            
            # Determine manifest path based on cluster type
            if self.config.cluster.type == 'kind':
                manifest_path = autotune_dir / 'manifests' / 'crc' / 'default-db-included-installation' / 'minikube' / 'kruize-crc-minikube.yaml'
            elif self.config.cluster.type == 'minikube':
                manifest_path = autotune_dir / 'manifests' / 'crc' / 'default-db-included-installation' / 'minikube' / 'kruize-crc-minikube.yaml'
            else:  # openshift
                manifest_path = autotune_dir / 'manifests' / 'crc' / 'default-db-included-installation' / 'openshift' / 'kruize-crc-openshift.yaml'
            
            if not manifest_path.exists():
                self.logger.error(f"❌ Kruize manifest not found: {manifest_path}")
                return None
            
            # Apply Kruize manifest
            self.logger.debug("Applying Kruize manifest...")
            run_command([
                'kubectl', 'apply', '-f', str(manifest_path), '-n', namespace
            ], timeout=120)
            
            # Wait for Kruize pods to be ready
            self.logger.debug("Waiting for Kruize pods to be ready...")
            
            # Check all kruize pods together every 5 seconds
            import time
            max_wait = 180
            elapsed = 0
            all_ready = False
            
            while elapsed < max_wait:
                # Check all three pods in one go
                kruize_ready = False
                ui_ready = False
                db_ready = False
                
                # Check kruize pod
                result = run_command([
                    'kubectl', 'get', 'pods', '-n', namespace,
                    '-l', 'app=kruize',
                    '-o', 'jsonpath={.items[*].status.conditions[?(@.type=="Ready")].status}'
                ], capture_output=True, check=False, timeout=10)
                if result.returncode == 0 and 'True' in result.stdout:
                    kruize_ready = True
                
                # Check kruize-ui-nginx pod
                result = run_command([
                    'kubectl', 'get', 'pods', '-n', namespace,
                    '-l', 'app=kruize-ui-nginx',
                    '-o', 'jsonpath={.items[*].status.conditions[?(@.type=="Ready")].status}'
                ], capture_output=True, check=False, timeout=10)
                if result.returncode == 0 and 'True' in result.stdout:
                    ui_ready = True
                
                # Check kruize-db pod
                result = run_command([
                    'kubectl', 'get', 'pods', '-n', namespace,
                    '-l', 'app=kruize-db',
                    '-o', 'jsonpath={.items[*].status.conditions[?(@.type=="Ready")].status}'
                ], capture_output=True, check=False, timeout=10)
                if result.returncode == 0 and 'True' in result.stdout:
                    db_ready = True
                
                # If all three are ready, break
                if kruize_ready and ui_ready and db_ready:
                    all_ready = True
                    self.logger.success("✅ All Kruize pods are ready")
                    break
                
                time.sleep(5)
                elapsed += 5
            
            if not all_ready:
                self.logger.warning("⚠️  Some Kruize pods not ready after timeout, but continuing...")
            
            # Setup port forwarding for kind cluster
            if self.config.cluster.type == 'kind':
                self.logger.debug("Setting up port forwarding for kind cluster...")
                
                # Kill any existing port-forwards first
                self.cluster_manager.kill_service_port_forward('kruize')
                self.cluster_manager.kill_service_port_forward('kruize-ui-nginx-service')
                
                # Port forward kruize service (8080:8080)
                self.logger.debug("Port forwarding kruize service...")
                self.cluster_manager.port_forward(
                    'service/kruize', namespace, 8080, 8080
                )
                
                # Port forward kruize-ui service (8081:8080)
                self.logger.debug("Port forwarding kruize-ui service...")
                self.cluster_manager.port_forward(
                    'service/kruize-ui-nginx-service', namespace, 8081, 8080
                )
                
                kruize_url = "http://127.0.0.1:8080"
            else:
                # For minikube/openshift, get service URL
                kruize_url = self.cluster_manager.get_service_url("kruize", namespace)
                if not kruize_url:
                    self.logger.error("❌ Failed to get Kruize service URL")
                    return None
            
            self.logger.success(f"✅ Kruize deployed successfully")
            
            # Give Kruize application time to fully initialize after pod is ready
            self.logger.info("⏳ Waiting for Kruize service to fully initialize...")
            time.sleep(20)
            self.logger.info("✅ Kruize service initialized!")
            
            return kruize_url
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"❌ Failed to deploy Kruize: {e}")
            return None
        except Exception as e:
            self.logger.error(f"❌ Unexpected error deploying Kruize: {e}")
            return None
    
    def _install_profiles(self) -> bool:
        """
        Install metric and metadata profiles
        Following bash script logic from lines 650-663
        
        Returns:
            True if successful
        """
        try:
            from pathlib import Path
            import json
            
            if not self.kruize_client:
                self.logger.warning("⚠️  Kruize client not initialized, skipping profile installation")
                return True
            
            self.logger.info("Installing metric and metadata profiles...")
            
            # Find autotune directory with profiles
            cloned_repos_dir = Path.cwd() / 'cloned_repos'
            autotune_dir = cloned_repos_dir / 'autotune'
            
            if not autotune_dir.exists():
                self.logger.warning("⚠️  Autotune directory not found, skipping profile installation")
                return True
            
            # Determine which metric profile to use based on cluster type
            if self.config.cluster.type == 'minikube':
                metric_profile_file = 'resource_optimization_local_monitoring_norecordingrules.json'
            else:
                metric_profile_file = 'resource_optimization_local_monitoring.json'
            
            # Install metric profile (resource optimization)
            resource_profile_path = autotune_dir / 'manifests' / 'autotune' / 'performance-profiles' / metric_profile_file
            if resource_profile_path.exists():
                try:
                    with open(resource_profile_path, 'r') as f:
                        profile_data = json.load(f)
                    self.logger.debug(f"Installing metric profile: {metric_profile_file}...")
                    self.kruize_client.create_metric_profile(profile_data)
                    self.logger.success("✅ Metric profile installed")
                except Exception as e:
                    self.logger.debug(f"Metric profile installation skipped or failed: {e}")
            else:
                self.logger.warning(f"⚠️  Metric profile not found: {resource_profile_path}")
            
            # Install metadata profile
            metadata_profile_path = autotune_dir / 'manifests' / 'autotune' / 'metadata-profiles' / 'bulk_cluster_metadata_local_monitoring.json'
            if metadata_profile_path.exists():
                try:
                    with open(metadata_profile_path, 'r') as f:
                        profile_data = json.load(f)
                    self.logger.debug("Installing metadata profile...")
                    self.kruize_client.create_metadata_profile(profile_data)
                    self.logger.success("✅ Metadata profile installed")
                except Exception as e:
                    self.logger.debug(f"Metadata profile installation skipped or failed: {e}")
            else:
                self.logger.warning(f"⚠️  Metadata profile not found: {metadata_profile_path}")
            
            self.logger.success("✅ Profiles installation complete")
            return True
            
        except Exception as e:
            self.logger.warning(f"⚠️  Profile installation failed: {e}")
            return True  # Don't fail the demo
    
    def _deploy_benchmarks(self) -> bool:
        """
        Deploy benchmark workloads dynamically based on config
        Following bash script benchmarks_install() from common_helper.sh lines 348-422
        
        Supports: tfb, petclinic, human-eval, ttm, llm-rag, sysbench
        
        Returns:
            True if successful
        """
        try:
            from core.utils import run_command
            from pathlib import Path
            
            # Get benchmark config (should be set by CLI or config)
            benchmarks = getattr(self.config.demo, 'benchmarks', [])
            app_namespace = getattr(self.config.demo, 'app_namespace', 'default')
            manifests = getattr(self.config.demo, 'benchmark_manifests', 'kruize-demos')
            
            # If no benchmarks specified, use default
            if not benchmarks:
                self.logger.info("No benchmarks specified, using default: tfb, sysbench")
                benchmarks = ['tfb', 'sysbench']
            
            # Create app namespace
            if not self.cluster_manager.create_namespace(app_namespace):
                self.logger.warning(f"⚠️  Failed to create namespace {app_namespace}")
            
            # Clone benchmarks repo if needed
            cloned_repos_dir = Path.cwd() / 'cloned_repos'
            benchmarks_dir = cloned_repos_dir / 'benchmarks'
            
            if not benchmarks_dir.exists():
                self.logger.debug("Cloning benchmarks repository...")
                run_command([
                    'git', 'clone',
                    'https://github.com/kruize/benchmarks.git',
                    str(benchmarks_dir)
                ], timeout=120)
            
            # Deploy each selected benchmark
            for benchmark in benchmarks:
                self.logger.info(f"📦 Deploying {benchmark} benchmark...")
                
                try:
                    if benchmark == 'tfb':
                        self._deploy_tfb(benchmarks_dir, app_namespace, manifests)
                    elif benchmark == 'petclinic':
                        self._deploy_petclinic(benchmarks_dir, app_namespace, manifests)
                    elif benchmark == 'sysbench':
                        self._deploy_sysbench(benchmarks_dir, app_namespace)
                    elif benchmark == 'human-eval':
                        self._deploy_human_eval(benchmarks_dir, app_namespace)
                    elif benchmark == 'ttm':
                        self._deploy_ttm(benchmarks_dir, app_namespace)
                    elif benchmark == 'llm-rag':
                        self._deploy_llm_rag(benchmarks_dir, app_namespace)
                    else:
                        self.logger.warning(f"⚠️  Unknown benchmark type: {benchmark}")
                        continue
                    
                    self.logger.success(f"✅ {benchmark} deployed successfully")
                except Exception as e:
                    self.logger.warning(f"⚠️  Failed to deploy {benchmark}: {e}")
            
            return True
            
        except Exception as e:
            self.logger.warning(f"⚠️  Benchmark deployment failed: {e}")
            return True  # Don't fail the demo
    
    def _prompt_benchmark_selection(self) -> list:
        """
        Prompt user to select benchmarks interactively
        
        Returns:
            List of selected benchmark names
        """
        available_benchmarks = {
            '1': ('tfb', 'TechEmpower (Quarkus REST EASY)'),
            '2': ('petclinic', 'Spring Petclinic'),
            '3': ('sysbench', 'Sysbench'),
            '4': ('human-eval', 'HumanEval (AI/ML)'),
            '5': ('ttm', 'Training TTM (AI/ML)'),
            '6': ('llm-rag', 'LLM-RAG (AI/ML)')
        }
        
        print("\n" + "="*60)
        print("Available Benchmarks:")
        print("="*60)
        for key, (name, desc) in available_benchmarks.items():
            print(f"  {key}. {desc}")
        print("="*60)
        print("\nSelect benchmarks to deploy:")
        print("  - Enter numbers separated by commas (e.g., 1,2,3)")
        print("  - Press Enter for default (tfb, sysbench)")
        print("  - Enter 'none' to skip benchmark deployment")
        print()
        
        try:
            selection = input("Your selection: ").strip()
            
            # Handle empty input (default)
            if not selection:
                self.logger.info("Using default benchmarks: tfb, sysbench")
                return ['tfb', 'sysbench']
            
            # Handle 'none'
            if selection.lower() == 'none':
                return []
            
            # Parse selection
            selected = []
            for num in selection.split(','):
                num = num.strip()
                if num in available_benchmarks:
                    benchmark_name = available_benchmarks[num][0]
                    selected.append(benchmark_name)
                else:
                    self.logger.warning(f"⚠️  Invalid selection: {num}")
            
            if selected:
                self.logger.info(f"Selected benchmarks: {', '.join(selected)}")
            else:
                self.logger.info("No valid benchmarks selected, using default: tfb, sysbench")
                selected = ['tfb', 'sysbench']
            
            return selected
            
        except (EOFError, KeyboardInterrupt):
            self.logger.info("\nUsing default benchmarks: tfb, sysbench")
            return ['tfb', 'sysbench']
    
    def _deploy_tfb(self, benchmarks_dir, namespace: str, manifests: str):
        """Deploy TechEmpower benchmark"""
        from core.utils import run_command, wait_for_pods_ready
        from pathlib import Path
        
        benchmarks_dir = Path(benchmarks_dir)
        
        self.logger.debug("Installing TechEmpower (Quarkus REST EASY) benchmark...")
        tfb_dir = benchmarks_dir / 'techempower'
        
        # Try kruize-demos manifests first, then fall back to specified manifests
        manifests_dir = tfb_dir / 'manifests' / 'kruize-demos'
        if not manifests_dir.exists():
            self.logger.debug(f"kruize-demos manifests not found, using {manifests}")
            manifests_dir = tfb_dir / 'manifests' / manifests
        else:
            self.logger.debug("Using kruize-demos manifests")
        
        if manifests_dir.exists():
            run_command([
                'kubectl', 'apply', '-f', str(manifests_dir), '-n', namespace
            ], timeout=120)
            
            # Wait for pods
            self.logger.debug("Waiting for TFB pods to be ready...")
            wait_for_pods_ready(namespace, 'app=tfb-qrh-sample', timeout=180)
        else:
            self.logger.warning(f"⚠️  TFB manifests not found at {manifests_dir}")
    
    def _deploy_petclinic(self, benchmarks_dir, namespace: str, manifests: str):
        """Deploy Spring Petclinic benchmark"""
        from core.utils import run_command, wait_for_pods_ready
        from pathlib import Path
        
        benchmarks_dir = Path(benchmarks_dir)
        
        self.logger.debug("Installing Spring Petclinic benchmark...")
        petclinic_dir = benchmarks_dir / 'spring-petclinic'
        
        # Try kruize-demos manifests first
        manifests_dir = petclinic_dir / 'manifests' / 'kruize-demos'
        if not manifests_dir.exists():
            self.logger.debug(f"kruize-demos manifests not found, using {manifests}")
            if manifests != 'default_manifests':
                manifests_dir = petclinic_dir / 'manifests' / manifests
            else:
                manifests_dir = petclinic_dir / 'manifests'
        else:
            self.logger.debug("Using kruize-demos manifests")
        
        if manifests_dir.exists():
            run_command([
                'kubectl', 'apply', '-f', str(manifests_dir), '-n', namespace
            ], timeout=120)
            
            # Wait for pods
            self.logger.debug("Waiting for Petclinic pods to be ready...")
            wait_for_pods_ready(namespace, 'app=petclinic', timeout=180)
        else:
            self.logger.warning(f"⚠️  Petclinic manifests not found at {manifests_dir}")
    
    def _deploy_sysbench(self, benchmarks_dir, namespace: str):
        """Deploy Sysbench"""
        from core.utils import run_command, wait_for_pods_ready
        from pathlib import Path
        
        benchmarks_dir = Path(benchmarks_dir)
        
        self.logger.debug("Installing Sysbench...")
        sysbench_dir = benchmarks_dir / 'sysbench'
        manifest = sysbench_dir / 'manifests' / 'sysbench.yaml'
        
        if manifest.exists():
            run_command([
                'kubectl', 'apply', '-f', str(manifest), '-n', namespace
            ], timeout=120)
            
            # Wait for pods
            self.logger.debug("Waiting for Sysbench pods to be ready...")
            wait_for_pods_ready(namespace, 'app=sysbench', timeout=180)
    
    def _deploy_human_eval(self, benchmarks_dir, namespace: str):
        """Deploy Human-Eval benchmark"""
        from core.utils import run_command
        from pathlib import Path
        
        benchmarks_dir = Path(benchmarks_dir)
        
        self.logger.debug("Running HumanEval benchmark job...")
        human_eval_dir = benchmarks_dir / 'human-eval-benchmark' / 'manifests'
        
        pvc_file = human_eval_dir / 'pvc.yaml'
        job_file = human_eval_dir / 'job.yaml'
        
        if pvc_file.exists() and job_file.exists():
            run_command([
                'kubectl', 'apply', '-f', str(pvc_file), '-n', namespace
            ], timeout=60)
            run_command([
                'kubectl', 'apply', '-f', str(job_file), '-n', namespace
            ], timeout=60)
    
    def _deploy_ttm(self, benchmarks_dir, namespace: str):
        """Deploy TTM benchmark"""
        self.logger.debug("TTM benchmark deployment not fully implemented yet")
    
    def _deploy_llm_rag(self, benchmarks_dir, namespace: str):
        """Deploy LLM-RAG benchmark"""
        self.logger.debug("LLM-RAG benchmark deployment not fully implemented yet")
    
    def _apply_benchmark_load(self) -> bool:
        """
        Apply load to deployed benchmarks
        Following bash script apply_benchmark_load() from common_helper.sh lines 477-535
        
        Supports load for: tfb, petclinic, llm-rag
        
        Returns:
            True if successful
        """
        try:
            from core.utils import run_command
            from pathlib import Path
            
            # Get config
            benchmarks = getattr(self.config.demo, 'benchmarks', [])
            app_namespace = getattr(self.config.demo, 'app_namespace', 'default')
            load_duration = getattr(self.config.demo, 'load_duration', 1200)
            cluster_type = self.config.cluster.type
            
            # Benchmarks that support load
            load_supporting_benchmarks = {'tfb', 'petclinic', 'llm-rag'}
            benchmarks_to_load = [b for b in benchmarks if b in load_supporting_benchmarks]
            
            if not benchmarks_to_load:
                self.logger.info("No load-supporting benchmarks selected")
                return True
            
            self.logger.info(f"Applying load to benchmarks: {', '.join(benchmarks_to_load)}")
            
            for benchmark in benchmarks_to_load:
                try:
                    if benchmark == 'tfb':
                        self._apply_tfb_load(app_namespace, load_duration, cluster_type)
                    elif benchmark == 'petclinic':
                        self._apply_petclinic_load(app_namespace, cluster_type)
                    elif benchmark == 'llm-rag':
                        self._apply_llm_rag_load(app_namespace)
                    
                    self.logger.success(f"✅ Load applied to {benchmark}")
                except Exception as e:
                    self.logger.warning(f"⚠️  Failed to apply load to {benchmark}: {e}")
            
            return True
            
        except Exception as e:
            self.logger.warning(f"⚠️  Benchmark load failed: {e}")
            return True  # Don't fail the demo
    
    def _apply_tfb_load(self, namespace: str, duration: int, cluster_type: str):
        """Apply load to TFB benchmark"""
        from core.utils import run_command
        
        # Check if tfb pods exist
        result = run_command([
            'kubectl', 'get', 'pods', '--namespace', namespace,
            '-o', 'jsonpath={.items[*].metadata.name}'
        ], capture_output=True, check=False, timeout=10)
        
        if result.returncode != 0 or 'tfb' not in result.stdout:
            self.logger.warning(f"⚠️  TFB pods not found in namespace {namespace}")
            return
        
        self.logger.info(f"Starting {duration} seconds background load against TFB benchmark in {namespace} namespace")
        
        # Determine TFB route based on cluster type
        if cluster_type in ['kind', 'minikube']:
            tfb_route = "localhost:8080"  # Default for local clusters
        else:
            self.logger.warning("⚠️  TFB load for non-local clusters not fully implemented")
            return
        
        # Run load using docker
        load_image = "quay.io/kruizehub/tfb_hyperfoil_load:0.25.2"
        try:
            run_command([
                'docker', 'run', '-d', '--rm', '--network=host',
                load_image,
                '/opt/run_hyperfoil_load.sh',
                tfb_route,
                'queries?queries=20',
                str(duration),
                '512',
                '4096'
            ], timeout=30)
            self.logger.success(f"✅ TFB load started for {duration} seconds")
        except Exception as e:
            self.logger.warning(f"⚠️  Failed to start TFB load: {e}")
    
    def _apply_petclinic_load(self, namespace: str, cluster_type: str):
        """Apply load to Petclinic benchmark"""
        # Check if petclinic pods exist
        from core.utils import run_command
        
        result = run_command([
            'kubectl', 'get', 'pods', '--namespace', namespace,
            '-o', 'jsonpath={.items[*].metadata.name}'
        ], capture_output=True, check=False, timeout=10)
        
        if result.returncode != 0 or 'petclinic' not in result.stdout:
            self.logger.warning(f"⚠️  Petclinic pods not found in namespace {namespace}")
            return
        
        self.logger.info(f"Starting background load against Petclinic benchmark in {namespace} namespace")
        # Note: Petclinic load script is commented out in bash script (lines 516-520)
        self.logger.warning("⚠️  Petclinic load not fully implemented (commented in bash script)")
    
    def _apply_llm_rag_load(self, namespace: str):
        """Apply load to LLM-RAG benchmark"""
        from core.utils import run_command
        from pathlib import Path
        
        # Check if llm pods exist
        result = run_command([
            'kubectl', 'get', 'pods', '--namespace', namespace,
            '-o', 'jsonpath={.items[*].metadata.name}'
        ], capture_output=True, check=False, timeout=10)
        
        if result.returncode != 0 or 'llm' not in result.stdout:
            self.logger.warning(f"⚠️  LLM-RAG pods not found in namespace {namespace}")
            return
        
        self.logger.info(f"Starting background load against LLM-RAG benchmark in {namespace} namespace")
        
        # Find benchmarks directory
        cloned_repos_dir = Path.cwd() / 'cloned_repos'
        llm_rag_dir = cloned_repos_dir / 'benchmarks' / 'AI-MLbenchmarks' / 'llm-rag'
        
        if not llm_rag_dir.exists():
            self.logger.warning(f"⚠️  LLM-RAG directory not found: {llm_rag_dir}")
            return
        
        try:
            # Run load script in background
            run_command([
                'bash', '-c',
                f'cd {llm_rag_dir} && ./run_load.sh {namespace} &'
            ], timeout=30)
            self.logger.success("✅ LLM-RAG load started")
        except Exception as e:
            self.logger.warning(f"⚠️  Failed to start LLM-RAG load: {e}")
    
    def _generate_experiment_from_template(
        self,
        template_type: str,
        namespace: str,
        workload_name: str = None,
        workload_type: str = "deployment",
        container_name: str = None,
        container_image: str = None
    ) -> dict:
        """
        Generate experiment from template by replacing placeholders
        
        Args:
            template_type: 'container' or 'namespace'
            namespace: Namespace name
            workload_name: Workload/deployment name (for container experiments)
            workload_type: Type of workload (deployment, statefulset, etc.)
            container_name: Container name (for container experiments)
            container_image: Container image (for container experiments)
            
        Returns:
            Experiment data dictionary
        """
        import json
        from pathlib import Path
        
        # Find template file
        template_paths = [
            Path('demo-v2/config/experiments'),
            Path('config/experiments'),
        ]
        
        template_file = None
        for template_path in template_paths:
            potential_file = template_path / f'{template_type}_experiment_template.json'
            if potential_file.exists():
                template_file = potential_file
                break
        
        if not template_file:
            raise FileNotFoundError(f"Template file for {template_type} not found")
        
        # Load template
        with open(template_file, 'r') as f:
            template_str = f.read()
        
        # Replace placeholders
        if template_type == 'container':
            template_str = template_str.replace('PLACEHOLDER_CONTAINER', container_name or workload_name)
            template_str = template_str.replace('PLACEHOLDER_WORKLOAD', workload_name)
            template_str = template_str.replace('PLACEHOLDER_WORKLOAD_TYPE', workload_type)
            template_str = template_str.replace('PLACEHOLDER_NAMESPACE_NAME', namespace)
            template_str = template_str.replace('PLACEHOLDER_IMAGE', container_image or 'unknown')
        elif template_type == 'namespace':
            template_str = template_str.replace('PLACEHOLDER_NAMESPACE_NAME', namespace)
        
        # Parse JSON - keep as array since Kruize API expects array format
        experiment_data = json.loads(template_str)
        
        return experiment_data
    
    def _create_experiments(self) -> bool:
        """
        Create monitoring experiments dynamically from templates
        
        Returns:
            True if successful
        """
        try:
            if not self.kruize_client:
                self.logger.error("❌ Kruize client not initialized")
                return False
            
            self.logger.info("Creating experiments from templates...")
            
            app_namespace = getattr(self.config.demo, 'app_namespace', 'default')
            benchmarks = getattr(self.config.demo, 'benchmarks', ['sysbench'])
            
            created_experiments = []
            
            # Create namespace experiment
            try:
                self.logger.info(f"🔄 Creating namespace experiment for: {app_namespace}")
                namespace_exp = self._generate_experiment_from_template(
                    template_type='namespace',
                    namespace=app_namespace
                )
                
                # Extract experiment name from array (for logging/tracking)
                exp_name = namespace_exp[0].get('experiment_name') if isinstance(namespace_exp, list) else namespace_exp.get('experiment_name')
                
                # Delete old experiment if exists
                try:
                    self.kruize_client.delete_experiment(exp_name)
                except:
                    pass
                
                # Create experiment - send as array
                response = self.kruize_client.create_experiment(namespace_exp)
                if response:
                    self.logger.success(f"✅ Created namespace experiment: {exp_name}")
                    created_experiments.append(exp_name)
            except Exception as e:
                self.logger.warning(f"⚠️  Failed to create namespace experiment: {e}")
            
            # Create container experiments for each benchmark
            benchmark_configs = {
                'sysbench': [
                    {'workload': 'sysbench', 'container': 'sysbench', 'image': 'quay.io/kruizehub/sysbench'}
                ],
                'tfb': [
                    {'workload': 'tfb-qrh-sample', 'container': 'tfb-server', 'image': 'kruize/tfb-qrh:1.13.2.F_et17'},
                    {'workload': 'tfb-database', 'container': 'tfb-database', 'image': 'kruize/tfb-postgres-openshift:latest'}
                ],
                'petclinic': [
                    {'workload': 'petclinic', 'container': 'petclinic', 'image': 'kruize/spring-petclinic:latest'}
                ]
            }
            
            for benchmark in benchmarks:
                if benchmark not in benchmark_configs:
                    self.logger.debug(f"No container config for benchmark: {benchmark}")
                    continue
                
                for config in benchmark_configs[benchmark]:
                    try:
                        self.logger.info(f"🔄 Creating container experiment for: {config['container']}")
                        container_exp = self._generate_experiment_from_template(
                            template_type='container',
                            namespace=app_namespace,
                            workload_name=config['workload'],
                            workload_type='deployment',
                            container_name=config['container'],
                            container_image=config['image']
                        )
                        
                        # Extract experiment name from array (for logging/tracking)
                        exp_name = container_exp[0].get('experiment_name') if isinstance(container_exp, list) else container_exp.get('experiment_name')
                        
                        # Delete old experiment if exists
                        try:
                            self.kruize_client.delete_experiment(exp_name)
                        except:
                            pass
                        
                        # Create experiment - send as array
                        response = self.kruize_client.create_experiment(container_exp)
                        if response:
                            self.logger.success(f"✅ Created container experiment: {exp_name}")
                            created_experiments.append(exp_name)
                    except Exception as e:
                        self.logger.warning(f"⚠️  Failed to create container experiment for {config['container']}: {e}")
            
            if not created_experiments:
                self.logger.warning("⚠️  No experiments created")
                return True
            
            self.logger.success(f"✅ Created {len(created_experiments)} experiment(s)")
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Failed to create experiments: {e}")
            return False
    
    def _get_experiments_for_benchmarks(self, benchmarks: list) -> list:
        """
        Map benchmarks to their corresponding experiment files
        
        Args:
            benchmarks: List of benchmark names
            
        Returns:
            List of experiment file names
        """
        benchmark_to_experiment = {
            'tfb': ['create_tfb_exp', 'create_tfb-db_exp'],
            'petclinic': ['create_petclinic_semeru_exp'],
            'sysbench': ['container_experiment_sysbench'],
            'human-eval': ['create_human_eval_exp'],
            'ttm': ['create_ttm_exp'],
            'llm-rag': ['create_llm_rag_exp']
        }
        
        experiments = []
        for benchmark in benchmarks:
            if benchmark in benchmark_to_experiment:
                experiments.extend(benchmark_to_experiment[benchmark])
        
        # Default to tfb if no experiments found
        if not experiments:
            experiments = ['create_tfb_exp']
        
        return experiments
    
    def _generate_recommendations(self) -> bool:
        """
        Generate recommendations
        Following bash script logic from lines 222-277
        
        Returns:
            True if successful
        """
        try:
            import json
            import time
            from pathlib import Path
            
            if not self.kruize_client:
                self.logger.error("❌ Kruize client not initialized")
                return False
            
            self.logger.info("Generating recommendations...")
            
            # Get experiment names from config
            experiments = getattr(self.config.demo, 'experiments', ['create_tfb_exp'])
            
            # Get experiments directory
            experiments_dir = Path('monitoring/local_monitoring/experiments')
            
            no_recommendations = False
            generated_count = 0
            
            for experiment in experiments:
                experiment_file = experiments_dir / f'{experiment}.json'
                if not experiment_file.exists():
                    continue
                
                try:
                    # Load experiment to get name
                    with open(experiment_file, 'r') as f:
                        experiment_data = json.load(f)
                    
                    experiment_name = experiment_data.get('experiment_name', experiment)
                    
                    # Generate recommendations
                    self.logger.info(f"🔄 Generating recommendations for: {experiment_name}")
                    
                    response = self.kruize_client.generate_recommendations(experiment_name)
                    
                    if response and 'Recommendations Are Available' in str(response):
                        self.logger.success(f"✅ Generated recommendations for: {experiment_name}")
                        generated_count += 1
                        
                        # Save recommendations to file
                        output_file = Path(f'{experiment}_recommendation.json')
                        with open(output_file, 'w') as f:
                            json.dump(response, f, indent=2)
                        self.logger.debug(f"📁 Saved to: {output_file}")
                    else:
                        self.logger.warning(f"⚠️  No recommendations generated for: {experiment_name}")
                        no_recommendations = True
                        
                except Exception as e:
                    self.logger.warning(f"⚠️  Error generating recommendations for {experiment}: {e}")
                    no_recommendations = True
            
            # Show message if no recommendations
            if no_recommendations:
                self.logger.info("")
                self.logger.info("🔔 AT LEAST TWO DATAPOINTS ARE REQUIRED TO GENERATE RECOMMENDATIONS!")
                self.logger.info("🔔 PLEASE WAIT FOR FEW MINS AND GENERATE THE RECOMMENDATIONS AGAIN.")
                self.logger.info("")
                self.logger.info("🔗 Generate fresh recommendations using:")
                for experiment in experiments:
                    experiment_file = experiments_dir / f'{experiment}.json'
                    if experiment_file.exists():
                        with open(experiment_file, 'r') as f:
                            experiment_data = json.load(f)
                        experiment_name = experiment_data.get('experiment_name', experiment)
                        kruize_url = getattr(self, '_kruize_url', 'http://127.0.0.1:8080')
                        self.logger.info(f"curl -X POST {kruize_url}/generateRecommendations?experiment_name={experiment_name}")
            elif generated_count > 0:
                self.logger.success(f"✅ Generated {generated_count} recommendation(s)")
            
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Failed to generate recommendations: {e}")
            return False
    
    def _print_next_steps(self, kruize_url: str):
        """Print next steps for user"""
        ui_url = kruize_url.replace(':8080', ':8081')
        
        self.logger.print_section("Next Steps")
        self.logger.info(f"1. Access Kruize UI: {ui_url}")
        self.logger.info(f"2. Access Kruize API: {kruize_url}")
        self.logger.info("3. View recommendations in the UI")
        self.logger.info("4. Apply recommendations to your workloads")
    
    def cleanup(self) -> bool:
        """Cleanup demo resources"""
        self.logger.print_header("Cleaning Up Demo Resources")
        
        try:
            # Cleanup Kruize
            # Cleanup benchmarks
            # Cleanup cluster (if setup by demo)
            
            if self.config.cluster.setup and self.cluster_manager:
                return self.cluster_manager.cleanup()
            
            return True
            
        except Exception as e:
            self.logger.error(f"Cleanup failed: {e}")
            return False

# Made with Bob
