"""
Base demo class for all Kruize demos
"""
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any
from datetime import datetime

from core.config import Config
from core.logger import get_logger
from core.cluster import ClusterManager
from api.client import KruizeClient


class BaseDemo(ABC):
    """Base class for all demo implementations"""
    
    def __init__(self, config: Config):
        """
        Initialize base demo
        
        Args:
            config: Configuration object
        """
        self.config = config
        self.logger = get_logger()
        self.cluster_manager: Optional[ClusterManager] = None
        self.kruize_client: Optional[KruizeClient] = None
        self.start_time: Optional[datetime] = None
        self.end_time: Optional[datetime] = None
    
    def setup_cluster(self) -> bool:
        """
        Setup Kubernetes cluster
        
        Returns:
            True if successful
        """
        cluster_type = self.config.cluster.type
        namespace = self.config.get_namespace(cluster_type)
        
        # Get cluster name from config or use default
        cluster_name = getattr(self.config.cluster, 'name', 'kruize-demo')
        
        self.cluster_manager = ClusterManager(cluster_type, namespace, cluster_name)
        
        # Setup cluster if requested (creates fresh cluster)
        if self.config.cluster.setup:
            self.logger.print_header(f"Setting up {cluster_type.capitalize()} Cluster")
            
            if cluster_type == "minikube":
                return self.cluster_manager.setup_minikube(
                    cpus=self.config.cluster.min_cpu,
                    memory=self.config.cluster.min_memory
                )
            elif cluster_type == "kind":
                return self.cluster_manager.setup_kind()
            else:
                self.logger.error(f"Cluster setup not supported for {cluster_type}")
                return False
        
        # If not setting up, check if cluster is already running and accessible
        if self.cluster_manager.is_running():
            self.logger.info(f"{cluster_type.capitalize()} cluster is already running")
            return True
        
        # For kind, try to use any existing cluster if the expected one doesn't exist
        if cluster_type == "kind":
            if self._try_use_existing_kind_cluster():
                return True
        
        self.logger.error(f"{cluster_type.capitalize()} cluster is not running or not accessible")
        self.logger.info(f"Please start your {cluster_type} cluster or use --setup flag")
        return False
    
    def _try_use_existing_kind_cluster(self) -> bool:
        """
        Try to use any existing kind cluster by exporting its kubeconfig
        
        Returns:
            True if successful
        """
        try:
            from core.utils import run_command
            
            # Get list of existing kind clusters
            result = run_command(['kind', 'get', 'clusters'],
                               check=False, capture_output=True)
            clusters = result.stdout.strip().split('\n') if result.stdout.strip() else []
            
            if not clusters:
                return False
            
            # Try to use the first available cluster
            cluster_name = clusters[0]
            self.logger.info(f"Found existing kind cluster: {cluster_name}")
            self.logger.info(f"Attempting to use it...")
            
            # Export kubeconfig for this cluster
            run_command(['kind', 'export', 'kubeconfig', '--name', cluster_name],
                      timeout=30)
            
            # Update cluster manager to use this cluster
            if self.cluster_manager:
                self.cluster_manager.cluster_name = cluster_name
                
                # Verify it's accessible
                if self.cluster_manager.is_running():
                    self.logger.success(f"Successfully configured to use kind cluster: {cluster_name}")
                    return True
            
            return False
            
        except Exception as e:
            self.logger.debug(f"Failed to use existing kind cluster: {e}")
            return False
    
    def setup_kruize_client(self, base_url: str) -> bool:
        """
        Setup Kruize API client
        
        Args:
            base_url: Kruize service URL
            
        Returns:
            True if successful
        """
        try:
            self.kruize_client = KruizeClient(
                base_url=base_url,
                timeout=self.config.api.timeout,
                retry_attempts=self.config.api.retry_attempts,
                retry_delay=self.config.api.retry_delay
            )
            
            # Health check
            if self.kruize_client.health_check():
                self.logger.success(f"Connected to Kruize at {base_url}")
                version = self.kruize_client.get_version()
                if version:
                    self.logger.info(f"Kruize version: {version}")
                return True
            else:
                self.logger.error("Kruize health check failed")
                return False
                
        except Exception as e:
            self.logger.error(f"Failed to setup Kruize client: {e}")
            return False
    
    def start_timer(self):
        """Start execution timer"""
        self.start_time = datetime.now()
    
    def stop_timer(self):
        """Stop execution timer"""
        self.end_time = datetime.now()
    
    def get_elapsed_time(self) -> int:
        """
        Get elapsed time in seconds
        
        Returns:
            Elapsed time in seconds
        """
        if self.start_time and self.end_time:
            return int((self.end_time - self.start_time).total_seconds())
        return 0
    
    def print_summary(self, success: bool, message: str = ""):
        """
        Print execution summary
        
        Args:
            success: Whether execution was successful
            message: Additional message
        """
        self.logger.print_header("Demo Execution Summary")
        
        if success:
            self.logger.print_success("Demo completed successfully!")
        else:
            self.logger.print_error("Demo failed!")
        
        if message:
            self.logger.info(message)
        
        if self.start_time and self.end_time:
            elapsed = self.get_elapsed_time()
            self.logger.print_time(f"Total execution time: {elapsed} seconds")
    
    @abstractmethod
    def run(self) -> bool:
        """
        Run the demo
        
        Returns:
            True if successful
        """
        pass
    
    @abstractmethod
    def cleanup(self) -> bool:
        """
        Cleanup demo resources
        
        Returns:
            True if successful
        """
        pass
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        if self.kruize_client:
            self.kruize_client.close()

# Made with Bob
