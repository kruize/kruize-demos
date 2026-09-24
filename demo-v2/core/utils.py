"""
Utility functions for Kruize Demos v2
"""
import os
import sys
import platform
import subprocess
import shutil
from datetime import datetime
from typing import Optional, Tuple, List, Dict, Any
from pathlib import Path


def check_prerequisites() -> Dict[str, bool]:
    """
    Check if all prerequisites are installed
    
    Returns:
        Dictionary with prerequisite status
    """
    prereqs = {
        'python': False,
        'kubectl': False,
        'docker': False,
        'git': False,
        'go': False
    }
    
    # Check Python
    prereqs['python'] = sys.version_info >= (3, 8)
    
    # Check kubectl
    prereqs['kubectl'] = shutil.which('kubectl') is not None
    
    # Check docker or podman
    prereqs['docker'] = shutil.which('docker') is not None or shutil.which('podman') is not None
    
    # Check git
    prereqs['git'] = shutil.which('git') is not None
    
    # Check go
    prereqs['go'] = shutil.which('go') is not None
    
    return prereqs


def check_go_version() -> Tuple[bool, str]:
    """
    Check if Go version meets requirements (>= 1.21)
    
    Returns:
        Tuple of (meets_requirement, version_string)
    """
    try:
        result = subprocess.run(
            ['go', 'version'],
            capture_output=True,
            text=True,
            check=True
        )
        version_str = result.stdout.strip()
        
        # Extract version number (e.g., "go1.21.0" -> "1.21.0")
        version_parts = version_str.split()
        if len(version_parts) >= 3:
            version = version_parts[2].replace('go', '')
            major, minor = map(int, version.split('.')[:2])
            
            # Check if version >= 1.21
            meets_req = (major > 1) or (major == 1 and minor >= 21)
            return meets_req, version_str
        
        return False, version_str
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError):
        return False, "Not installed"


def run_command(
    command: List[str],
    cwd: Optional[str] = None,
    env: Optional[Dict[str, str]] = None,
    capture_output: bool = True,
    check: bool = True,
    shell: bool = False,
    timeout: Optional[int] = None
) -> subprocess.CompletedProcess:
    """
    Run a shell command
    
    Args:
        command: Command to run as list
        cwd: Working directory
        env: Environment variables
        capture_output: Capture stdout/stderr
        check: Raise exception on non-zero exit
        shell: Run in shell
        timeout: Command timeout in seconds
        
    Returns:
        CompletedProcess instance
        
    Note:
        Command and output are always logged to file for debugging.
        Terminal shows clean output by default.
    """
    from .logger import get_logger
    logger = get_logger()
    
    if shell and isinstance(command, list):
        cmd_str = ' '.join(command)
    else:
        cmd_str = command if isinstance(command, str) else ' '.join(command)
    
    # Always log command to file
    logger.debug(f"Executing command: {cmd_str}")
    if cwd:
        logger.debug(f"Working directory: {cwd}")
    
    # Run command
    if shell and isinstance(command, list):
        cmd_to_run = cmd_str
    else:
        cmd_to_run = command
    
    result = subprocess.run(
        cmd_to_run,
        cwd=cwd,
        env=env,
        capture_output=capture_output,
        text=True,
        check=check,
        shell=shell,
        timeout=timeout
    )
    
    # Log output to file (not terminal)
    if result.stdout:
        logger.debug(f"Command stdout:\n{result.stdout}")
    if result.stderr:
        logger.debug(f"Command stderr:\n{result.stderr}")
    logger.debug(f"Command exit code: {result.returncode}")
    
    return result


def time_diff(start_time: datetime, end_time: datetime) -> int:
    """
    Calculate time difference in seconds
    
    Args:
        start_time: Start datetime
        end_time: End datetime
        
    Returns:
        Difference in seconds
    """
    return int((end_time - start_time).total_seconds())


def format_duration(seconds: int) -> str:
    """
    Format duration in human-readable format
    
    Args:
        seconds: Duration in seconds
        
    Returns:
        Formatted duration string
    """
    if seconds < 60:
        return f"{seconds} seconds"
    elif seconds < 3600:
        minutes = seconds // 60
        secs = seconds % 60
        return f"{minutes} minutes {secs} seconds"
    else:
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        return f"{hours} hours {minutes} minutes"


def get_system_info() -> Dict[str, Any]:
    """
    Get system information
    
    Returns:
        Dictionary with system info
    """
    info = {
        'os': platform.system(),
        'os_version': platform.version(),
        'architecture': platform.machine(),
        'python_version': platform.python_version(),
        'cpu_count': os.cpu_count() or 0
    }
    
    # Get memory info based on OS
    if info['os'] == 'Linux':
        try:
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
                for line in meminfo.split('\n'):
                    if line.startswith('MemTotal:'):
                        # Convert KB to MB
                        info['memory_mb'] = int(line.split()[1]) // 1024
                        break
        except:
            info['memory_mb'] = 0
    elif info['os'] == 'Darwin':  # macOS
        try:
            result = subprocess.run(
                ['sysctl', '-n', 'hw.memsize'],
                capture_output=True,
                text=True,
                check=True
            )
            # Convert bytes to MB
            info['memory_mb'] = int(result.stdout.strip()) // (1024 * 1024)
        except:
            info['memory_mb'] = 0
    else:
        info['memory_mb'] = 0
    
    return info


def validate_resources(min_cpu: int = 8, min_memory: int = 16384) -> Tuple[bool, str]:
    """
    Validate system resources meet minimum requirements
    
    Args:
        min_cpu: Minimum CPU cores required
        min_memory: Minimum memory in MB required
        
    Returns:
        Tuple of (meets_requirements, message)
    """
    sys_info = get_system_info()
    
    cpu_count = sys_info['cpu_count']
    memory_mb = sys_info['memory_mb']
    
    issues = []
    
    if cpu_count < min_cpu:
        issues.append(f"CPU: {cpu_count} cores (minimum {min_cpu} required)")
    
    if memory_mb < min_memory:
        issues.append(f"Memory: {memory_mb} MB (minimum {min_memory} MB required)")
    
    if issues:
        message = "System does not meet minimum requirements:\n" + "\n".join(f"  - {issue}" for issue in issues)
        return False, message
    
    return True, "System meets minimum requirements"


def ensure_directory(path: str) -> Path:
    """
    Ensure directory exists, create if not
    
    Args:
        path: Directory path
        
    Returns:
        Path object
    """
    dir_path = Path(path)
    dir_path.mkdir(parents=True, exist_ok=True)
    return dir_path


def find_file(filename: str, search_paths: List[str]) -> Optional[str]:
    """
    Find file in search paths
    
    Args:
        filename: File to find
        search_paths: List of paths to search
        
    Returns:
        Full path to file if found, None otherwise
    """
    for search_path in search_paths:
        file_path = Path(search_path) / filename
        if file_path.exists():
            return str(file_path)
    return None


def clone_repo(repo_name: str, target_dir: Optional[str] = None) -> bool:
    """
    Clone kruize repository (follows common_helper.sh pattern)
    
    Args:
        repo_name: Repository name (e.g., 'autotune', 'benchmarks')
        target_dir: Target directory (defaults to repo_name)
        
    Returns:
        True if successful, False otherwise
    """
    from .logger import get_logger
    logger = get_logger()
    
    if target_dir is None:
        target_dir = repo_name
    
    try:
        # Check if directory already exists
        if Path(target_dir).exists():
            logger.debug(f"Repository {repo_name} already exists at {target_dir}")
            return True
        
        # Try SSH first, then HTTPS
        ssh_url = f"git@github.com:kruize/{repo_name}.git"
        https_url = f"https://github.com/kruize/{repo_name}.git"
        
        logger.debug(f"Cloning {repo_name} repository...")
        
        # Try SSH
        result = run_command(['git', 'clone', ssh_url, target_dir],
                           capture_output=True, check=False, timeout=120)
        
        if result.returncode != 0:
            # Try HTTPS
            logger.debug("SSH clone failed, trying HTTPS...")
            run_command(['git', 'clone', https_url, target_dir],
                       capture_output=True, timeout=120)
        
        logger.debug(f"Successfully cloned {repo_name}")
        return True
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to clone {repo_name}: {e}")
        return False
    except subprocess.TimeoutExpired:
        logger.error(f"Timeout while cloning {repo_name}")
        return False


def get_kubectl_context() -> Optional[str]:
    """
    Get current kubectl context
    
    Returns:
        Current context name or None
    """
    try:
        result = run_command(
            ['kubectl', 'config', 'current-context'],
            capture_output=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def check_cluster_running(cluster_type: str, cluster_name: str = "kruize-demo") -> bool:
    """
    Check if cluster is running and kubectl is properly configured
    
    Args:
        cluster_type: Type of cluster (minikube, kind, openshift)
        cluster_name: Name of the cluster (for kind)
        
    Returns:
        True if running and accessible, False otherwise
    """
    try:
        if cluster_type == "minikube":
            result = run_command(['minikube', 'status'], capture_output=True, check=False)
            if 'Running' not in result.stdout:
                return False
            # Verify kubectl can access the cluster
            result = run_command(['kubectl', 'cluster-info'], capture_output=True, check=False, timeout=10)
            return result.returncode == 0
            
        elif cluster_type == "kind":
            # Check if any kind clusters exist
            result = run_command(['kind', 'get', 'clusters'], capture_output=True, check=False)
            clusters = result.stdout.strip().split('\n') if result.stdout.strip() else []
            
            if not clusters or cluster_name not in clusters:
                return False
            
            # Verify kubectl context is set correctly
            try:
                context_result = run_command(['kubectl', 'config', 'current-context'],
                                           capture_output=True, check=False, timeout=10)
                current_context = context_result.stdout.strip()
                
                # Check if context matches the expected kind cluster
                if current_context != f'kind-{cluster_name}':
                    return False
                
                # Verify kubectl can actually access the cluster
                cluster_result = run_command(['kubectl', 'cluster-info'],
                                           capture_output=True, check=False, timeout=10)
                return cluster_result.returncode == 0
            except subprocess.TimeoutExpired:
                return False
                
        elif cluster_type == "openshift":
            result = run_command(['oc', 'whoami'], capture_output=True, check=False)
            return result.returncode == 0
        else:
            # Generic kubectl check
            result = run_command(['kubectl', 'cluster-info'], capture_output=True, check=False, timeout=10)
            return result.returncode == 0
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return False


def wait_for_pod_ready(
    pod_name: str,
    namespace: str,
    timeout: int = 300,
    interval: int = 5
) -> bool:
    """
    Wait for pod to be ready
    
    Args:
        pod_name: Pod name or label selector
        namespace: Namespace
        timeout: Timeout in seconds
        interval: Check interval in seconds
        
    Returns:
        True if pod is ready, False if timeout
    """
    import time
    
    elapsed = 0
    while elapsed < timeout:
        try:
            result = run_command(
                ['kubectl', 'get', 'pod', '-n', namespace, '-l', pod_name,
                 '-o', 'jsonpath={.items[0].status.phase}'],
                capture_output=True,
                check=False
            )
            
            if result.stdout.strip() == 'Running':
                return True
        except:
            pass
        
        time.sleep(interval)
        elapsed += interval
    
    return False


def wait_for_pods_ready(
    namespace: str,
    label_selector: Optional[str] = None,
    timeout: int = 300,
    interval: int = 5
) -> bool:
    """
    Wait for all pods in namespace to be ready
    
    Args:
        namespace: Namespace to check
        label_selector: Label selector (e.g., 'app=kruize')
        timeout: Timeout in seconds
        interval: Check interval in seconds
        
    Returns:
        True if all pods are ready, False if timeout
    """
    from .logger import get_logger
    logger = get_logger()
    
    import time
    elapsed = 0
    
    cmd = ['kubectl', 'get', 'pods', '-n', namespace]
    if label_selector:
        cmd.extend(['-l', label_selector])
    cmd.extend(['-o', 'jsonpath={.items[*].status.conditions[?(@.type=="Ready")].status}'])
    
    while elapsed < timeout:
        try:
            result = run_command(cmd, capture_output=True, check=False, timeout=10)
            
            if result.returncode == 0:
                statuses = result.stdout.strip().split()
                if statuses and all(status == 'True' for status in statuses):
                    logger.debug(f"All pods in {namespace} are ready")
                    return True
            
        except subprocess.TimeoutExpired:
            pass
        except Exception as e:
            logger.debug(f"Error checking pod status: {e}")
        
        time.sleep(interval)
        elapsed += interval
    
    logger.warning(f"Timeout waiting for pods in {namespace} to be ready")
    return False

# Made with Bob
