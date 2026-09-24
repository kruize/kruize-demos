"""
Configuration management for Kruize Demos v2
"""
import os
import yaml
from pathlib import Path
from typing import Any, Dict, Optional
from dataclasses import dataclass, field


@dataclass
class ClusterConfig:
    """Cluster configuration"""
    type: str = "kind"
    setup: bool = False
    min_cpu: int = 8
    min_memory: int = 16384


@dataclass
class KruizeConfig:
    """Kruize service configuration"""
    image: str = "quay.io/kruize/autotune_operator:latest"
    ui_image: str = "quay.io/kruize/kruize-ui:latest"
    operator_image: str = "quay.io/kruize/kruize-operator:latest"
    use_operator: bool = True
    port: int = 8080
    ui_port: int = 8081
    prometheus_port: int = 9090
    namespace_minikube: str = "monitoring"
    namespace_kind: str = "monitoring"
    namespace_openshift: str = "openshift-tuning"


@dataclass
class DemoConfig:
    """Demo execution configuration"""
    namespace: str = "default"
    load_duration: int = 1200
    wait_time: int = 0
    deploy_benchmark: bool = False
    benchmarks: list = None  # List of benchmarks to deploy
    app_namespace: str = "default"  # Namespace for benchmark apps
    run_load: bool = False
    benchmark_manifests: str = "resource_provisioning_manifests"
    experiments: list = None  # List of experiments to create
    experiment_type: str = ""
    expose_prometheus: bool = False
    
    def __post_init__(self):
        """Initialize mutable defaults"""
        if self.benchmarks is None:
            self.benchmarks = []
        if self.experiments is None:
            self.experiments = []


@dataclass
class LoggingConfig:
    """Logging configuration"""
    level: str = "INFO"
    file: str = "kruize-demo.log"
    format: str = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    console_output: bool = True


@dataclass
class APIConfig:
    """API configuration"""
    timeout: int = 30
    retry_attempts: int = 3
    retry_delay: int = 5


@dataclass
class PathsConfig:
    """Paths configuration"""
    experiments: str = "experiments"
    manifests: str = "manifests"
    data: str = "data"
    logs: str = "logs"
    temp: str = "temp"


class Config:
    """Main configuration class for Kruize Demos"""
    
    def __init__(self, config_file: Optional[str] = None):
        """
        Initialize configuration
        
        Args:
            config_file: Path to YAML configuration file
        """
        self.config_file = config_file or self._find_config_file()
        self._config_data: Dict[str, Any] = {}
        self._load_config()
        
        # Initialize configuration sections
        self.cluster = ClusterConfig(**self._config_data.get('cluster', {}))
        self.kruize = KruizeConfig(**self._config_data.get('kruize', {}))
        self.demo = DemoConfig(**self._config_data.get('demo', {}))
        self.logging = LoggingConfig(**self._config_data.get('logging', {}))
        self.api = APIConfig(**self._config_data.get('api', {}))
        self.paths = PathsConfig(**self._config_data.get('paths', {}))
        
        # Additional configurations
        self.remote_monitoring = self._config_data.get('remote_monitoring', {})
        self.bulk = self._config_data.get('bulk', {})
    
    def _find_config_file(self) -> str:
        """Find configuration file in standard locations"""
        search_paths = [
            'config.yaml',
            'config.yml',
            os.path.join(os.path.dirname(__file__), '..', 'config.yaml'),
            os.path.expanduser('~/.kruize/config.yaml'),
            '/etc/kruize/config.yaml'
        ]
        
        for path in search_paths:
            if os.path.exists(path):
                return path
        
        # Return default path if not found
        return os.path.join(os.path.dirname(__file__), '..', 'config.yaml')
    
    def _load_config(self):
        """Load configuration from YAML file"""
        if os.path.exists(self.config_file):
            with open(self.config_file, 'r') as f:
                self._config_data = yaml.safe_load(f) or {}
        else:
            # Use default configuration
            self._config_data = self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """Get default configuration"""
        return {
            'cluster': {},
            'kruize': {},
            'demo': {},
            'logging': {},
            'api': {},
            'paths': {},
            'remote_monitoring': {'data_days': 1, 'visualize': False},
            'bulk': {'wait_time': 0}
        }
    
    def update(self, section: str, key: str, value: Any):
        """
        Update configuration value
        
        Args:
            section: Configuration section
            key: Configuration key
            value: New value
        """
        if hasattr(self, section):
            section_obj = getattr(self, section)
            if hasattr(section_obj, key):
                setattr(section_obj, key, value)
    
    def get(self, section: str, key: str, default: Any = None) -> Any:
        """
        Get configuration value
        
        Args:
            section: Configuration section
            key: Configuration key
            default: Default value if not found
            
        Returns:
            Configuration value
        """
        if hasattr(self, section):
            section_obj = getattr(self, section)
            return getattr(section_obj, key, default)
        return default
    
    def get_namespace(self, cluster_type: str) -> str:
        """
        Get namespace for cluster type
        
        Args:
            cluster_type: Type of cluster (kind, minikube, openshift)
            
        Returns:
            Namespace name
        """
        if cluster_type == "minikube":
            return self.kruize.namespace_minikube
        elif cluster_type == "kind":
            return self.kruize.namespace_kind
        elif cluster_type == "openshift":
            return self.kruize.namespace_openshift
        else:
            return "monitoring"
    
    def save(self, output_file: Optional[str] = None):
        """
        Save configuration to file
        
        Args:
            output_file: Output file path (defaults to current config file)
        """
        output_file = output_file or self.config_file
        
        config_dict = {
            'cluster': self.cluster.__dict__,
            'kruize': self.kruize.__dict__,
            'demo': self.demo.__dict__,
            'logging': self.logging.__dict__,
            'api': self.api.__dict__,
            'paths': self.paths.__dict__,
            'remote_monitoring': self.remote_monitoring,
            'bulk': self.bulk
        }
        
        with open(output_file, 'w') as f:
            yaml.dump(config_dict, f, default_flow_style=False)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert configuration to dictionary"""
        return {
            'cluster': self.cluster.__dict__,
            'kruize': self.kruize.__dict__,
            'demo': self.demo.__dict__,
            'logging': self.logging.__dict__,
            'api': self.api.__dict__,
            'paths': self.paths.__dict__,
            'remote_monitoring': self.remote_monitoring,
            'bulk': self.bulk
        }
    
    def __repr__(self) -> str:
        """String representation"""
        return f"Config(file={self.config_file})"

# Made with Bob
