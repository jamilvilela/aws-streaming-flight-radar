"""UI module — Rich-powered console output for the deploy toolkit."""

from __future__ import annotations

import sys
from typing import Optional

from rich.align import Align
from rich.box import DOUBLE_EDGE, ROUNDED, HEAVY_HEADER
from rich.console import Console as RichConsole
from rich.live import Live
from rich.markdown import Markdown
from rich.panel import Panel
from rich.progress import (
    BarColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TimeElapsedColumn,
)
from rich.table import Table
from rich.text import Text
from rich.tree import Tree


console = RichConsole()

# ── Style constants ──────────────────────────────────────────────────────
STYLE_SUCCESS = "bold green"
STYLE_ERROR = "bold red"
STYLE_WARNING = "bold yellow"
STYLE_INFO = "bold blue"
STYLE_HEADER = "bold white on blue"
STYLE_MUTED = "dim white"
STYLE_ACCENT = "cyan"
STYLE_VALUE = "yellow"


# ── Section helpers ──────────────────────────────────────────────────────

def section_header(title: str, subtitle: Optional[str] = None) -> None:
    """Print a prominent section header."""
    text = Text()
    text.append(f"\n{'=' * 60}\n", style=STYLE_MUTED)
    text.append(f"  {title}", style=STYLE_HEADER)
    if subtitle:
        text.append(f"\n  {subtitle}", style=STYLE_MUTED)
    text.append(f"\n{'=' * 60}", style=STYLE_MUTED)
    console.print(Panel(text, box=HEAVY_HEADER, padding=(0, 1)))


def step_header(title: str) -> None:
    """Print a step header (like 'STEP 1')."""
    console.print(f"\n[bold blue]◆ {title}[/bold blue]")


# ── Status indicators ────────────────────────────────────────────────────

def ok(message: str, detail: str = "") -> None:
    """Print a success message."""
    prefix = "✅"
    if detail:
        console.print(f"  {prefix} [bold green]{message}[/bold green] [dim]{detail}[/dim]")
    else:
        console.print(f"  {prefix} [bold green]{message}[/bold green]")


def fail(message: str, detail: str = "") -> None:
    """Print a failure message."""
    prefix = "❌"
    if detail:
        console.print(f"  {prefix} [bold red]{message}[/bold red] [dim]{detail}[/dim]")
    else:
        console.print(f"  {prefix} [bold red]{message}[/bold red]")


def warn(message: str, detail: str = "") -> None:
    """Print a warning message."""
    prefix = "⚠️"
    if detail:
        console.print(f"  {prefix} [bold yellow]{message}[/bold yellow] [dim]{detail}[/dim]")
    else:
        console.print(f"  {prefix} [bold yellow]{message}[/bold yellow]")


def info(message: str, detail: str = "") -> None:
    """Print an informational message."""
    prefix = "ℹ️"
    if detail:
        console.print(f"  {prefix} [cyan]{message}[/cyan] [dim]{detail}[/dim]")
    else:
        console.print(f"  {prefix} [cyan]{message}[/cyan]")


# ── Data display ─────────────────────────────────────────────────────────

def print_output(name: str, value: str, sensitive: bool = False) -> None:
    """Print a Terraform-style output key=value pair."""
    val_style = STYLE_WARNING if sensitive else "white"
    label = f"  [bold]{name}[/bold]"
    if sensitive:
        label += " [red](sensitive)[/red]"
    console.print(f"{label} = [{val_style}]{value}[/{val_style}]")


def print_output_group(title: str, items: list[tuple[str, str, bool]]) -> None:
    """Print a group of outputs under a section title."""
    console.print(f"\n  [bold cyan]── {title} ──[/bold cyan]")
    for name, value, sensitive in items:
        print_output(name, value, sensitive)


# ── Tables ───────────────────────────────────────────────────────────────

def resource_table(title: str, columns: list[str], rows: list[list[str]]) -> Table:
    """Create a styled table for resource listings."""
    table = Table(
        title=title,
        box=ROUNDED,
        header_style="bold cyan",
        title_style="bold",
        border_style="blue",
    )
    for col in columns:
        table.add_column(col, overflow="fold")
    for row in rows:
        table.add_row(*row)
    return table


# ── Progress / Live display ──────────────────────────────────────────────

def create_progress(description: str = "Working...") -> Progress:
    """Create a standard progress bar."""
    return Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        TimeElapsedColumn(),
        console=console,
    )


class ProgressTracker:
    """Context manager that renders a live-updating progress display."""

    def __init__(self, description: str = "Processing..."):
        self._description = description
        self._progress = create_progress(description)
        self._task_id: Optional[int] = None
        self._live: Optional[Live] = None

    def __enter__(self):
        self._live = Live(self._progress, console=console, refresh_per_second=10)
        self._live.__enter__()
        self._task_id = self._progress.add_task(
            f"[cyan]{self._description}[/cyan]",
            total=100,
        )
        return self

    def __exit__(self, *args):
        if self._live:
            self._live.__exit__(*args)
        self._live = None
        self._task_id = None

    def update(self, progress: int, description: Optional[str] = None) -> None:
        """Update progress percentage and optional description."""
        if self._task_id is not None and self._progress:
            self._progress.update(self._task_id, completed=progress)
            if description:
                self._progress.update(
                    self._task_id,
                    description=f"[cyan]{description}[/cyan]",
                )


# ── Summary panel ────────────────────────────────────────────────────────

def summary_panel(
    title: str,
    items: list[tuple[str, str]],
    border_style: str = "green",
) -> Panel:
    """Create a summary panel with key-value items."""
    text = Text()
    for i, (key, value) in enumerate(items):
        if i > 0:
            text.append("\n")
        text.append(f"  {key}: ", style="bold")
        text.append(value, style=STYLE_VALUE)
    return Panel(
        Align.left(text),
        title=f"[bold]{title}[/bold]",
        border_style=border_style,
        box=DOUBLE_EDGE,
        padding=(1, 2),
    )


# ── Tree display ─────────────────────────────────────────────────────────

def resource_tree(title: str) -> Tree:
    """Create a styled tree for hierarchical resource display."""
    tree = Tree(
        f"[bold cyan]{title}[/bold cyan]",
        guide_style="dim cyan",
    )
    return tree


# ── Error handling ───────────────────────────────────────────────────────

def display_error(message: str, details: Optional[str] = None) -> None:
    """Display an error in a styled panel."""
    text = Text(f"\n  {message}", style="bold red")
    if details:
        text.append(f"\n\n  {details}", style="dim white")
    console.print(
        Panel(
            text,
            title="[bold red]Error[/bold red]",
            border_style="red",
            box=ROUNDED,
        )
    )
