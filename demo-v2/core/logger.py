"""
Logging utilities for Kruize Demos v2
"""
import logging
import sys
from pathlib import Path
from typing import Optional
from rich.console import Console
from rich.logging import RichHandler
from loguru import logger as loguru_logger


class Logger:
    """Custom logger with rich console output"""
    
    def __init__(self, name: str, level: str = "INFO", log_file: Optional[str] = None):
        """
        Initialize logger
        
        Args:
            name: Logger name
            level: Logging level
            log_file: Log file path
        """
        self.name = name
        self.level = level
        self.log_file = log_file
        self.console = Console()
        
        # Setup loguru
        self._setup_loguru()
    
    def _setup_loguru(self):
        """Setup loguru logger"""
        # Remove default handler
        loguru_logger.remove()
        
        # Add console handler with rich formatting
        loguru_logger.add(
            sys.stderr,
            format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan> - <level>{message}</level>",
            level=self.level,
            colorize=True
        )
        
        # Add file handler if specified
        if self.log_file:
            log_path = Path(self.log_file)
            log_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Clear the log file at the start of each demo run
            if log_path.exists():
                log_path.unlink()
            
            loguru_logger.add(
                self.log_file,
                format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name}:{function} - {message}",
                level="DEBUG",  # Always log everything to file
                rotation="10 MB",
                retention="7 days",
                compression="zip"
            )
    
    def debug(self, message: str, **kwargs):
        """Log debug message"""
        loguru_logger.debug(message, **kwargs)
    
    def info(self, message: str, **kwargs):
        """Log info message"""
        loguru_logger.info(message, **kwargs)
    
    def warning(self, message: str, **kwargs):
        """Log warning message"""
        loguru_logger.warning(message, **kwargs)
    
    def error(self, message: str, **kwargs):
        """Log error message"""
        loguru_logger.error(message, **kwargs)
    
    def critical(self, message: str, **kwargs):
        """Log critical message"""
        loguru_logger.critical(message, **kwargs)
    
    def success(self, message: str, **kwargs):
        """Log success message"""
        loguru_logger.success(message, **kwargs)
    
    def print_header(self, text: str, style: str = "bold cyan"):
        """Print formatted header"""
        self.console.print(f"\n{'=' * 60}", style=style)
        self.console.print(f"{text:^60}", style=style)
        self.console.print(f"{'=' * 60}\n", style=style)
    
    def print_section(self, text: str, style: str = "bold yellow"):
        """Print formatted section"""
        self.console.print(f"\n{'-' * 60}", style=style)
        self.console.print(f"{text}", style=style)
        self.console.print(f"{'-' * 60}", style=style)
    
    def print_success(self, text: str):
        """Print success message"""
        self.console.print(f"✅ {text}", style="bold green")
    
    def print_error(self, text: str):
        """Print error message"""
        self.console.print(f"❌ {text}", style="bold red")
    
    def print_warning(self, text: str):
        """Print warning message"""
        self.console.print(f"⚠️  {text}", style="bold yellow")
    
    def print_info(self, text: str):
        """Print info message"""
        self.console.print(f"ℹ️  {text}", style="bold blue")
    
    def print_progress(self, text: str):
        """Print progress message"""
        self.console.print(f"🔄 {text}", style="bold cyan")
    
    def print_time(self, text: str):
        """Print time message"""
        self.console.print(f"🕒 {text}", style="bold magenta")


# Global logger instance
_logger: Optional[Logger] = None


def setup_logger(name: str = "kruize-demo", level: str = "INFO", log_file: Optional[str] = None) -> Logger:
    """
    Setup and return logger instance
    
    Args:
        name: Logger name
        level: Logging level
        log_file: Log file path
        
    Returns:
        Logger instance
    """
    global _logger
    _logger = Logger(name, level, log_file)
    return _logger


def get_logger() -> Logger:
    """
    Get logger instance
    
    Returns:
        Logger instance
    """
    global _logger
    if _logger is None:
        _logger = setup_logger()
    return _logger

# Made with Bob
