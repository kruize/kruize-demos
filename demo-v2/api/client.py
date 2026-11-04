"""
Kruize API client implementation
"""
import json
import time
from typing import Optional, Dict, Any, List
from urllib.parse import urljoin
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .exceptions import (
    KruizeAPIError,
    KruizeConnectionError,
    KruizeValidationError,
    KruizeTimeoutError,
    KruizeNotFoundError,
    KruizeServerError
)


class KruizeClient:
    """Client for interacting with Kruize REST API"""
    
    def __init__(
        self,
        base_url: str,
        timeout: int = 30,
        retry_attempts: int = 3,
        retry_delay: int = 5
    ):
        """
        Initialize Kruize API client
        
        Args:
            base_url: Base URL of Kruize service
            timeout: Request timeout in seconds
            retry_attempts: Number of retry attempts
            retry_delay: Delay between retries in seconds
        """
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.retry_attempts = retry_attempts
        self.retry_delay = retry_delay
        
        # Setup session with retry logic
        self.session = requests.Session()
        retry_strategy = Retry(
            total=retry_attempts,
            backoff_factor=retry_delay,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "OPTIONS", "POST", "PUT"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)
    
    def _make_request(
        self,
        method: str,
        endpoint: str,
        data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
        headers: Optional[Dict[str, str]] = None
    ) -> requests.Response:
        """
        Make HTTP request to Kruize API
        
        Args:
            method: HTTP method
            endpoint: API endpoint
            data: Request body data
            params: Query parameters
            headers: Request headers
            
        Returns:
            Response object
            
        Raises:
            KruizeAPIError: On API errors
        """
        url = urljoin(self.base_url + '/', endpoint.lstrip('/'))
        
        default_headers = {'Content-Type': 'application/json'}
        if headers:
            default_headers.update(headers)
        
        try:
            response = self.session.request(
                method=method,
                url=url,
                json=data,
                params=params,
                headers=default_headers,
                timeout=self.timeout
            )
            
            # Handle different status codes
            if response.status_code == 404:
                raise KruizeNotFoundError(
                    f"Resource not found: {endpoint}",
                    status_code=response.status_code,
                    response=response.text
                )
            elif response.status_code >= 500:
                raise KruizeServerError(
                    f"Server error: {response.text}",
                    status_code=response.status_code,
                    response=response.text
                )
            elif response.status_code >= 400:
                raise KruizeValidationError(
                    f"Validation error: {response.text}",
                    status_code=response.status_code,
                    response=response.text
                )
            
            return response
            
        except requests.exceptions.Timeout:
            raise KruizeTimeoutError(f"Request timed out after {self.timeout} seconds")
        except requests.exceptions.ConnectionError as e:
            raise KruizeConnectionError(f"Failed to connect to Kruize: {e}")
        except requests.exceptions.RequestException as e:
            raise KruizeAPIError(f"Request failed: {e}")
    
    def create_experiment(self, experiment_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a new experiment
        
        Args:
            experiment_data: Experiment configuration
            
        Returns:
            Response data
        """
        response = self._make_request('POST', '/createExperiment', data=experiment_data)
        return response.json() if response.text else {}
    
    def update_results(self, results_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Update experiment results
        
        Args:
            results_data: Results data
            
        Returns:
            Response data
        """
        response = self._make_request('POST', '/updateResults', data=results_data)
        return response.json() if response.text else {}
    
    def list_recommendations(
        self,
        experiment_name: Optional[str] = None,
        latest: Optional[bool] = None,
        monitoring_end_time: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        List recommendations for experiments
        
        Args:
            experiment_name: Filter by experiment name
            latest: Get only latest recommendations
            monitoring_end_time: Filter by monitoring end time
            
        Returns:
            Recommendations data
        """
        params = {}
        if experiment_name:
            params['experiment_name'] = experiment_name
        if latest is not None:
            params['latest'] = str(latest).lower()
        if monitoring_end_time:
            params['monitoring_end_time'] = monitoring_end_time
        
        response = self._make_request('GET', '/listRecommendations', params=params)
        return response.json() if response.text else {}
    
    def list_experiments(self) -> Dict[str, Any]:
        """
        List all experiments
        
        Returns:
            Experiments data
        """
        response = self._make_request('GET', '/listExperiments')
        return response.json() if response.text else {}
    
    def create_performance_profile(self, profile_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create performance profile
        
        Args:
            profile_data: Performance profile configuration
            
        Returns:
            Response data
        """
        response = self._make_request('POST', '/createPerformanceProfile', data=profile_data)
        return response.json() if response.text else {}
    
    def create_metric_profile(self, profile_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create metric profile
        
        Args:
            profile_data: Metric profile configuration
            
        Returns:
            Response data
        """
        response = self._make_request('POST', '/createMetricProfile', data=profile_data)
        return response.json() if response.text else {}
    
    def create_metadata_profile(self, profile_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create metadata profile
        
        Args:
            profile_data: Metadata profile configuration
            
        Returns:
            Response data
        """
        response = self._make_request('POST', '/createMetadataProfile', data=profile_data)
        return response.json() if response.text else {}
    
    def delete_experiment(self, experiment_name: str) -> Dict[str, Any]:
        """
        Delete an experiment
        
        Args:
            experiment_name: Name of experiment to delete
            
        Returns:
            Response data
        """
        response = self._make_request('DELETE', '/createExperiment', params={'experiment_name': experiment_name})
        return response.json() if response.text else {}
    
    def generate_recommendations(self, experiment_name: str) -> Dict[str, Any]:
        """
        Generate recommendations for an experiment
        
        Args:
            experiment_name: Name of experiment
            
        Returns:
            Recommendations data
        """
        response = self._make_request('POST', '/generateRecommendations', params={'experiment_name': experiment_name})
        return response.json() if response.text else {}
    
    def bulk_service(self, bulk_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Submit bulk job
        
        Args:
            bulk_data: Bulk job configuration
            
        Returns:
            Job information including job_id
        """
        response = self._make_request('POST', '/bulk', data=bulk_data)
        return response.json() if response.text else {}
    
    def get_bulk_job_status(
        self,
        job_id: str,
        include: Optional[str] = None,
        experiment_name: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Get bulk job status
        
        Args:
            job_id: Job ID
            include: What to include in response (summary, experiments)
            experiment_name: Filter by experiment name
            
        Returns:
            Job status data
        """
        params = {'job_id': job_id}
        if include:
            params['include'] = include
        if experiment_name:
            params['experiment_name'] = experiment_name
        
        response = self._make_request('GET', '/bulk', params=params)
        return response.json() if response.text else {}
    
    def wait_for_bulk_job(
        self,
        job_id: str,
        timeout: int = 600,
        poll_interval: int = 10
    ) -> Dict[str, Any]:
        """
        Wait for bulk job to complete
        
        Args:
            job_id: Job ID
            timeout: Maximum wait time in seconds
            poll_interval: Polling interval in seconds
            
        Returns:
            Final job status
            
        Raises:
            KruizeTimeoutError: If job doesn't complete within timeout
        """
        start_time = time.time()
        
        while True:
            elapsed = time.time() - start_time
            if elapsed > timeout:
                raise KruizeTimeoutError(
                    f"Bulk job {job_id} did not complete within {timeout} seconds"
                )
            
            status = self.get_bulk_job_status(job_id, include="summary")
            job_status = status.get('summary', {}).get('status')
            
            if job_status == 'COMPLETED':
                return self.get_bulk_job_status(job_id, include="summary,experiments")
            elif job_status == 'FAILED':
                raise KruizeAPIError(
                    f"Bulk job {job_id} failed: {status.get('summary', {}).get('notifications')}"
                )
            
            time.sleep(poll_interval)
    
    def health_check(self) -> bool:
        """
        Check if Kruize service is healthy
        
        Returns:
            True if healthy, False otherwise
        """
        try:
            response = self._make_request('GET', '/health')
            return response.status_code == 200
        except:
            return False
    
    def get_version(self) -> Optional[str]:
        """
        Get Kruize version
        
        Returns:
            Version string or None
        """
        try:
            response = self._make_request('GET', '/version')
            data = response.json()
            return data.get('version')
        except:
            return None
    
    def close(self):
        """Close the session"""
        self.session.close()
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()

# Made with Bob
