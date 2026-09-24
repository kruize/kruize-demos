"""
Custom exceptions for Kruize API client
"""


class KruizeAPIError(Exception):
    """Base exception for Kruize API errors"""
    
    def __init__(self, message: str, status_code: int = None, response: str = None):
        self.message = message
        self.status_code = status_code
        self.response = response
        super().__init__(self.message)
    
    def __str__(self):
        if self.status_code:
            return f"[{self.status_code}] {self.message}"
        return self.message


class KruizeConnectionError(KruizeAPIError):
    """Exception raised when connection to Kruize fails"""
    pass


class KruizeValidationError(KruizeAPIError):
    """Exception raised when request validation fails"""
    pass


class KruizeTimeoutError(KruizeAPIError):
    """Exception raised when request times out"""
    pass


class KruizeNotFoundError(KruizeAPIError):
    """Exception raised when resource is not found"""
    pass


class KruizeServerError(KruizeAPIError):
    """Exception raised when server returns 5xx error"""
    pass

# Made with Bob
