"""UI module — simple print-based console output (no Rich dependency)."""

from __future__ import annotations

import re
import sys
from typing import Optional


class _SimpleConsole:
    """Minimal console wrapper — mimics RichConsole.print() with plain print."""

    @staticmethod
    def print(*args, **kwargs) -> None:
        """Print to stdout (RichConsole.print compatibility shim)."""
        text = args[0] if args else ""
        if isinstance(text, str):
            # Remove simple Rich markup like [bold green]...[/bold green]
            text = re.sub(r"\[/?\w+(?:\s+\w+)?\]", "", text)
        print(text)


console = _SimpleConsole()


# ── ANSI helpers ─────────────────────────────────────────────────────────

def _bold(s: str) -> str:
    return f"\033[1m{s}\033[0m"

def _green(s: str) -> str:
    return f"\033[32m{s}\033[0m"

def _red(s: str) -> str:
    return f"\033[31m{s}\033[0m"

def _yellow(s: str) -> str:
    return f"\033[33m{s}\033[0m"

def _cyan(s: str) -> str:
    return f"\033[36m{s}\033[0m"

def _dim(s: str) -> str:
    return f"\033[2m{s}\033[0m"

def _bold_green(s: str) -> str:
    return _bold(_green(s))

def _bold_red(s: str) -> str:
    return _bold(_red(s))

def _bold_yellow(s: str) -> str:
    return _bold(_yellow(s))

def _bold_cyan(s: str) -> str:
    return _bold(_cyan(s))


# ── Section helpers ──────────────────────────────────────────────────────

def section_header(title: str, subtitle: Optional[str] = None) -> None:
    """Print a prominent section header."""
    line = "=" * 70
    print()
    print(_dim(line))
    print(f"  {_bold(title)}")
    if subtitle:
        print(f"  {_dim(subtitle)}")
    print(_dim(line))


def step_header(title: str) -> None:
    """Print a step header (like 'STEP 1')."""
    print(f"\n  {_bold_cyan(chr(9670))} {_bold(title)}")


# ── Status indicators ────────────────────────────────────────────────────

def ok(message: str, detail: str = "") -> None:
    """Print a success message."""
    prefix = "OK"
    if detail:
        print(f"  [{_bold_green(prefix)}] {_bold_green(message)} {_dim(detail)}")
    else:
        print(f"  [{_bold_green(prefix)}] {_bold_green(message)}")


def fail(message: str, detail: str = "") -> None:
    """Print a failure message."""
    prefix = "FAIL"
    if detail:
        print(f"  [{_bold_red(prefix)}] {_bold_red(message)} {_dim(detail)}")
    else:
        print(f"  [{_bold_red(prefix)}] {_bold_red(message)}")


def warn(message: str, detail: str = "") -> None:
    """Print a warning message."""
    prefix = "WARN"
    if detail:
        print(f"  [{_bold_yellow(prefix)}] {_bold_yellow(message)} {_dim(detail)}")
    else:
        print(f"  [{_bold_yellow(prefix)}] {_bold_yellow(message)}")


def info(message: str, detail: str = "") -> None:
    """Print an informational message."""
    prefix = "INFO"
    if detail:
        print(f"  [{_cyan(prefix)}] {_cyan(message)} {_dim(detail)}")
    else:
        print(f"  [{_cyan(prefix)}] {_cyan(message)}")


# ── Data display ─────────────────────────────────────────────────────────

def print_output(name: str, value: str, sensitive: bool = False) -> None:
    """Print a Terraform-style output key=value pair."""
    label = f"  {_bold(name)}"
    if sensitive:
        label += _red(" (sensitive)")
    print(f"{label} = {value}")


def print_output_group(title: str, items: list[tuple[str, str, bool]]) -> None:
    """Print a group of outputs under a section title."""
    print(f"\n  {_bold_cyan('--- ' + title + ' ---')}")
    for name, value, sensitive in items:
        print_output(name, value, sensitive)


# ── Tables ───────────────────────────────────────────────────────────────

def resource_table(title: str, columns: list[str], rows: list[list[str]]) -> None:
    """Print a simple text table for resource listings."""
    print(f"\n  {_bold(title)}")
    header = "  " + " | ".join(columns)
    sep = "  " + "-+-".join("-" * len(c) for c in columns)
    print(header)
    print(sep)
    for row in rows:
        print("  " + " | ".join(row))


# ── Progress (stub) ─────────────────────────────────────────────────────

def create_progress(description: str = "Working...") -> None:
    """Stub — progress bar not available in console mode."""
    print(f"  {description}...")


class ProgressTracker:
    """Simple stub — prints progress messages instead of live display."""

    def __init__(self, description: str = "Processing..."):
        self._description = description

    def __enter__(self):
        print(f"  {self._description}...")
        return self

    def __exit__(self, *args):
        done = args[0] is None or args[0] is False
        if done:
            print(f"  [OK] {self._description} — conclu\xaddo")
        else:
            print(f"  [FAIL] {self._description} — falhou")

    def update(self, progress: int, description: Optional[str] = None) -> None:
        """Update progress (prints at 25%, 50%, 75%, 100%)."""
        if progress in (25, 50, 75):
            print(f"    {progress}%")
        elif progress == 100:
            print(f"    [OK] 100%")


# ── Summary panel ────────────────────────────────────────────────────────

def summary_panel(title: str, items: list[tuple[str, str]], border_style: str = "green") -> str:
    """Return a formatted summary string (was a Rich Panel)."""
    border = "\u2500"
    color_fn = _green if border_style == "green" else _red

    lines = []
    lines.append(f"  {color_fn('\u250c' + border * 60 + '\u2510')}")
    lines.append(f"  {color_fn('\u2502')}  {_bold(title)}")
    lines.append(f"  {color_fn('\u251c' + border * 60 + '\u2524')}")
    for key, value in items:
        lines.append(f"  {color_fn('\u2502')}  {_bold(f'{key}:')} {value}")
    lines.append(f"  {color_fn('\u2514' + border * 60 + '\u2518')}")
    return "\n".join(lines)


# ── Tree display (stub) ─────────────────────────────────────────────────

def resource_tree(title: str) -> str:
    """Create a simple indented title (was a Rich Tree)."""
    return _bold_cyan(title)


# ── Error handling ───────────────────────────────────────────────────────

def display_error(message: str, details: Optional[str] = None) -> None:
    """Display an error message."""
    border = "\u2500"
    print()
    print(f"  {_red('\u250c' + border * 60 + '\u2510')}")
    print(f"  {_red('\u2502')}  {_bold_red('Error')}")
    print(f"  {_red('\u251c' + border * 60 + '\u2524')}")
    print(f"  {_red('\u2502')}  {_bold_red(message)}")
    if details:
        print(f"  {_red('\u2502')}")
        print(f"  {_red('\u2502')}  {_dim(details)}")
    print(f"  {_red('\u2514' + border * 60 + '\u2518')}")
    print()
