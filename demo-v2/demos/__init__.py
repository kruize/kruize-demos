"""
Demo implementations for Kruize v2
"""
from .local_monitoring import LocalMonitoringDemo
from .remote_monitoring import RemoteMonitoringDemo
from .bulk_demo import BulkDemo
from .gpu_demo import GPUDemo
from .vpa_demo import VPADemo
from .optimizer_demo import OptimizerDemo
from .runtimes_demo import RuntimesDemo
from .hpo_demo import HPODemo

__all__ = [
    'LocalMonitoringDemo',
    'RemoteMonitoringDemo',
    'BulkDemo',
    'GPUDemo',
    'VPADemo',
    'OptimizerDemo',
    'RuntimesDemo',
    'HPODemo'
]

# Made with Bob
