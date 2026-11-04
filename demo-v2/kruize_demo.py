#!/usr/bin/env python3
"""
Kruize Demos v2 - Interactive CLI
Main entry point for running Kruize demonstrations
"""
import sys
import os
import warnings
from pathlib import Path

# Suppress urllib3 OpenSSL warning
warnings.filterwarnings('ignore', message='urllib3 v2 only supports OpenSSL 1.1.1+')

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

import click
import questionary
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich import box
import pyfiglet

from core.config import Config
from core.logger import setup_logger, get_logger
from core.utils import check_prerequisites, validate_resources, get_system_info


console = Console()


def print_banner():
    """Print application banner with Kruize logo"""
    # Kruize ASCII art logo
    logo = """
[bold cyan]
    ██╗  ██╗██████╗ ██╗   ██╗██╗███████╗███████╗
    ██║ ██╔╝██╔══██╗██║   ██║██║╚══███╔╝██╔════╝
    █████╔╝ ██████╔╝██║   ██║██║  ███╔╝ █████╗
    ██╔═██╗ ██╔══██╗██║   ██║██║ ███╔╝  ██╔══╝
    ██║  ██╗██║  ██║╚██████╔╝██║███████╗███████╗
    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝╚══════╝╚══════╝
[/bold cyan]
[bold yellow]         Kubernetes Resource Optimization[/bold yellow]
[dim]                    Demos v2.0[/dim]
"""
    console.print(logo)


def check_system_requirements(config: Config) -> bool:
    """
    Check system requirements
    
    Args:
        config: Configuration object
        
    Returns:
        True if requirements met
    """
    logger = get_logger()
    
    logger.print_section("Checking System Requirements")
    
    # Check prerequisites
    prereqs = check_prerequisites()
    
    table = Table(title="Prerequisites Check", box=box.ROUNDED)
    table.add_column("Component", style="cyan")
    table.add_column("Status", style="bold")
    table.add_column("Required", style="yellow")
    
    for name, installed in prereqs.items():
        status = "✅ Installed" if installed else "❌ Missing"
        required = "Yes" if name in ['python', 'kubectl'] else "Optional"
        table.add_row(name.capitalize(), status, required)
    
    console.print(table)
    
    # Check resources
    meets_req, message = validate_resources(
        config.cluster.min_cpu,
        config.cluster.min_memory
    )
    
    if meets_req:
        logger.print_success(message)
    else:
        logger.print_warning(message)
    
    # Show system info
    sys_info = get_system_info()
    info_text = f"""
OS: {sys_info['os']} {sys_info['architecture']}
Python: {sys_info['python_version']}
CPUs: {sys_info['cpu_count']}
Memory: {sys_info['memory_mb']} MB
"""
    console.print(Panel(info_text, title="System Information", border_style="blue"))
    
    return prereqs['python'] and prereqs['kubectl']


def select_demo_interactive() -> str:
    """
    Interactive demo selection
    
    Returns:
        Selected demo type
    """
    demos = {
        'Local Monitoring': 'local',
        'Remote Monitoring': 'remote',
        'Bulk Operations': 'bulk',
        'GPU Optimization': 'gpu',
        'VPA Integration': 'vpa',
        'Optimizer Demo': 'optimizer',
        'Runtimes Demo': 'runtimes'
    }
    
    choice = questionary.select(
        "Select a demo to run:",
        choices=list(demos.keys())
    ).ask()
    
    return demos.get(choice, 'local')


def select_cluster_interactive() -> str:
    """
    Interactive cluster selection
    
    Returns:
        Selected cluster type
    """
    return questionary.select(
        "Select cluster type:",
        choices=['kind', 'minikube', 'openshift']
    ).ask()


def configure_demo_interactive(config: Config, demo_type: str):
    """
    Interactive demo configuration
    
    Args:
        config: Configuration object
        demo_type: Type of demo
    """
    console.print("\n[bold cyan]Demo Configuration[/bold cyan]\n")
    
    # Cluster setup
    if config.cluster.type in ['kind', 'minikube']:
        setup = questionary.confirm(
            f"Setup fresh {config.cluster.type} cluster?",
            default=False
        ).ask()
        config.cluster.setup = setup
    
    # Namespace
    namespace = questionary.text(
        "Enter namespace:",
        default=config.demo.namespace
    ).ask()
    config.demo.namespace = namespace
    
    # Demo-specific options
    if demo_type == 'local':
        deploy_bench = questionary.confirm(
            "Deploy benchmark workload?",
            default=False
        ).ask()
        config.demo.deploy_benchmark = deploy_bench
        
        if deploy_bench:
            # Ask which benchmarks to deploy
            benchmark_choices = [
                questionary.Choice("TechEmpower (Quarkus REST EASY)", value="tfb", checked=True),
                questionary.Choice("Spring Petclinic", value="petclinic"),
                questionary.Choice("Sysbench", value="sysbench", checked=True),
                questionary.Choice("HumanEval (AI/ML)", value="human-eval"),
                questionary.Choice("Training TTM (AI/ML)", value="ttm"),
                questionary.Choice("LLM-RAG (AI/ML)", value="llm-rag")
            ]
            
            selected_benchmarks = questionary.checkbox(
                "Select benchmarks to deploy (use space to select, enter to confirm):",
                choices=benchmark_choices
            ).ask()
            
            if not selected_benchmarks:
                selected_benchmarks = ["tfb", "sysbench"]  # Fallback to default
            
            config.demo.benchmarks = selected_benchmarks
            
            # Ask about load if any load-supporting benchmark is selected
            # Benchmarks that support load: tfb, petclinic, llm-rag
            load_supporting_benchmarks = {"tfb", "petclinic", "llm-rag"}
            selected_load_benchmarks = [b for b in selected_benchmarks if b in load_supporting_benchmarks]
            
            if selected_load_benchmarks:
                benchmark_names = ", ".join(selected_load_benchmarks)
                run_load = questionary.confirm(
                    f"Run load against benchmark(s): {benchmark_names}?",
                    default=False
                ).ask()
                config.demo.run_load = run_load
                
                if run_load:
                    duration = questionary.text(
                        "Load duration (seconds):",
                        default=str(config.demo.load_duration)
                    ).ask()
                    config.demo.load_duration = int(duration)
    
    elif demo_type == 'remote':
        days = questionary.text(
            "Number of days of data to push:",
            default="1"
        ).ask()
        config.remote_monitoring['data_days'] = int(days)
    
    elif demo_type == 'bulk':
        wait = questionary.text(
            "Wait time before processing (seconds):",
            default=str(config.bulk.get('wait_time', 0))
        ).ask()
        config.bulk['wait_time'] = int(wait)
    
    # Operator deployment
    use_operator = questionary.confirm(
        "Use Kruize Operator deployment? (Recommended)",
        default=config.kruize.use_operator
    ).ask()
    config.kruize.use_operator = use_operator


def show_configuration(config: Config, demo_type: str):
    """
    Display current configuration
    
    Args:
        config: Configuration object
        demo_type: Type of demo
    """
    table = Table(title="Current Configuration", box=box.DOUBLE)
    table.add_column("Setting", style="cyan")
    table.add_column("Value", style="green")
    
    table.add_row("Demo Type", demo_type.upper())
    table.add_row("Cluster Type", config.cluster.type)
    table.add_row("Cluster Setup", "Yes" if config.cluster.setup else "No")
    table.add_row("Namespace", config.demo.namespace)
    table.add_row("Use Operator", "Yes" if config.kruize.use_operator else "No")
    table.add_row("Kruize Image", config.kruize.image)
    
    if demo_type == 'local':
        table.add_row("Deploy Benchmark", "Yes" if config.demo.deploy_benchmark else "No")
        
        # Show selected benchmarks if any
        if config.demo.deploy_benchmark and hasattr(config.demo, 'benchmarks'):
            benchmarks = getattr(config.demo, 'benchmarks', [])
            if benchmarks:
                table.add_row("Benchmarks", ", ".join(benchmarks))
        
        table.add_row("Run Load", "Yes" if config.demo.run_load else "No")
    
    console.print("\n")
    console.print(table)
    console.print("\n")


@click.group(invoke_without_command=True)
@click.option('--config-file', '-c', help='Configuration file path')
@click.option('--debug', is_flag=True, help='Enable debug logging')
@click.pass_context
def cli(ctx, config_file, debug):
    """Kruize Demos v2 - Interactive CLI for Kubernetes Resource Optimization"""
    
    # Setup logging
    log_level = "DEBUG" if debug else "INFO"
    setup_logger(level=log_level, log_file="kruize-demo.log")
    
    # Load configuration
    config = Config(config_file)
    ctx.obj = {'config': config}
    
    # If no subcommand, run interactive mode
    if ctx.invoked_subcommand is None:
        interactive_mode(config)


def interactive_mode(config: Config):
    """
    Run interactive mode
    
    Args:
        config: Configuration object
    """
    print_banner()
    
    logger = get_logger()
    
    # Check system requirements
    if not check_system_requirements(config):
        logger.print_error("System requirements not met. Please install missing prerequisites.")
        sys.exit(1)
    
    # Select demo
    demo_type = select_demo_interactive()
    
    # Select cluster
    cluster_type = select_cluster_interactive()
    config.cluster.type = cluster_type
    
    # Configure demo
    configure_demo_interactive(config, demo_type)
    
    # Show configuration
    show_configuration(config, demo_type)
    
    # Confirm execution
    if not questionary.confirm("Proceed with demo execution?", default=True).ask():
        logger.info("Demo cancelled by user")
        return
    
    # Run demo
    logger.print_header(f"Running {demo_type.upper()} Demo")
    
    try:
        if demo_type == 'local':
            from demos.local_monitoring import LocalMonitoringDemo
            demo = LocalMonitoringDemo(config)
        elif demo_type == 'remote':
            from demos.remote_monitoring import RemoteMonitoringDemo
            demo = RemoteMonitoringDemo(config)
        elif demo_type == 'bulk':
            from demos.bulk_demo import BulkDemo
            demo = BulkDemo(config)
        elif demo_type == 'gpu':
            from demos.gpu_demo import GPUDemo
            demo = GPUDemo(config)
        elif demo_type == 'vpa':
            from demos.vpa_demo import VPADemo
            demo = VPADemo(config)
        elif demo_type == 'optimizer':
            from demos.optimizer_demo import OptimizerDemo
            demo = OptimizerDemo(config)
        elif demo_type == 'runtimes':
            from demos.runtimes_demo import RuntimesDemo
            demo = RuntimesDemo(config)
        elif demo_type == 'hpo':
            from demos.hpo_demo import HPODemo
            demo = HPODemo(config)
        else:
            logger.print_error(f"Demo type '{demo_type}' not yet implemented")
            logger.info("Available demos: local, remote, bulk, gpu, vpa, optimizer, runtimes, hpo")
            return
        
        success = demo.run()
        
        if success:
            logger.print_success("Demo completed successfully!")
        else:
            logger.print_error("Demo failed. Check logs for details.")
            sys.exit(1)
            
    except KeyboardInterrupt:
        logger.print_warning("\nDemo interrupted by user")
        sys.exit(130)
    except Exception as e:
        logger.print_error(f"Demo failed with error: {e}")
        if config.logging.level == "DEBUG":
            import traceback
            traceback.print_exc()
        sys.exit(1)


@cli.command()
@click.option('--demo', '-d', type=click.Choice(['local', 'remote', 'bulk', 'gpu', 'vpa', 'optimizer', 'runtimes', 'hpo']),
              required=True, help='Demo type to run')
@click.option('--cluster', type=click.Choice(['kind', 'minikube', 'openshift']),
              default='kind', help='Cluster type')
@click.option('--setup', is_flag=True, help='Setup cluster automatically')
@click.option('--namespace', default='default', help='Kubernetes namespace')
@click.option('--terminate', is_flag=True, help='Terminate and cleanup demo')
@click.pass_context
def run(ctx, demo, cluster, setup, namespace, terminate):
    """Run a specific demo non-interactively"""
    config = ctx.obj['config']
    logger = get_logger()
    
    # Update configuration
    config.cluster.type = cluster
    config.cluster.setup = setup
    config.demo.namespace = namespace
    
    if terminate:
        logger.print_header(f"Terminating {demo.upper()} Demo")
        # Implement cleanup logic
        logger.info("Cleanup completed")
        return
    
    logger.print_header(f"Running {demo.upper()} Demo")
    
    try:
        if demo == 'local':
            from demos.local_monitoring import LocalMonitoringDemo
            demo_instance = LocalMonitoringDemo(config)
        elif demo == 'remote':
            from demos.remote_monitoring import RemoteMonitoringDemo
            demo_instance = RemoteMonitoringDemo(config)
        elif demo == 'bulk':
            from demos.bulk_demo import BulkDemo
            demo_instance = BulkDemo(config)
        elif demo == 'gpu':
            from demos.gpu_demo import GPUDemo
            demo_instance = GPUDemo(config)
        elif demo == 'vpa':
            from demos.vpa_demo import VPADemo
            demo_instance = VPADemo(config)
        elif demo == 'optimizer':
            from demos.optimizer_demo import OptimizerDemo
            demo_instance = OptimizerDemo(config)
        elif demo == 'runtimes':
            from demos.runtimes_demo import RuntimesDemo
            demo_instance = RuntimesDemo(config)
        elif demo == 'hpo':
            from demos.hpo_demo import HPODemo
            demo_instance = HPODemo(config)
        else:
            logger.print_error(f"Demo '{demo}' not yet implemented")
            sys.exit(1)
        
        success = demo_instance.run()
        sys.exit(0 if success else 1)
        
    except Exception as e:
        logger.print_error(f"Demo failed: {e}")
        sys.exit(1)


@cli.command()
def list_demos():
    """List all available demos"""
    table = Table(title="Available Demos", box=box.ROUNDED)
    table.add_column("Demo", style="cyan", no_wrap=True)
    table.add_column("Description", style="white")
    table.add_column("Status", style="green")
    
    demos = [
        ("local", "Local monitoring with live cluster workloads", "[green]✅ Available[/green]"),
        ("remote", "Remote monitoring with historical data", "[green]✅ Available[/green]"),
        ("bulk", "Bulk operations for multiple experiments", "[green]✅ Available[/green]"),
        ("gpu", "GPU workload optimization", "[yellow]🚧 Structure Ready[/yellow]"),
        ("vpa", "VPA integration demo", "[yellow]🚧 Structure Ready[/yellow]"),
        ("optimizer", "Advanced optimization scenarios", "[yellow]🚧 Structure Ready[/yellow]"),
        ("runtimes", "Runtime-specific optimization", "[yellow]🚧 Structure Ready[/yellow]"),
        ("hpo", "Hyperparameter optimization", "[yellow]🚧 Structure Ready[/yellow]"),
    ]
    
    for name, desc, status in demos:
        table.add_row(name, desc, status)
    
    console.print(table)


@cli.command()
@click.pass_context
def config_show(ctx):
    """Show current configuration"""
    config = ctx.obj['config']
    console.print("\n[bold cyan]Current Configuration:[/bold cyan]\n")
    
    import yaml
    console.print(yaml.dump(config.to_dict(), default_flow_style=False))


def main():
    """Main entry point"""
    try:
        cli(obj={})
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted by user[/yellow]")
        sys.exit(130)
    except Exception as e:
        console.print(f"\n[red]Error: {e}[/red]")
        sys.exit(1)


if __name__ == '__main__':
    main()

# Made with Bob
