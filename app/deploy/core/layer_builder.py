"""Lambda Layer builder — pip install dependencies with platform targeting."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

from ..ui import console


class LambdaLayerBuilder:
    """Builds the Python Lambda Layer from requirements.txt."""

    def __init__(
        self,
        requirements_file: Path,
        layer_root: Path,
        python_bin: str = "python3",
        python_version: str = "3.12",
    ):
        self._req_file = requirements_file
        self._layer_root = layer_root
        self._sitepackages = layer_root / "python"
        self._checksum_file = layer_root / ".layer-checksum"
        self._python_bin = python_bin
        self._python_version = python_version

    def build_if_needed(self) -> bool:
        """
        Build the Lambda Layer if requirements changed.
        Returns True if layer is ready, False on failure.
        """
        console.step_header("STEP 3 — Construindo dependências da Lambda Layer")

        if not self._req_file.exists():
            console.fail(f"Arquivo de requirements não encontrado: {self._req_file}")
            return False

        current_hash = self._compute_hash()
        stored_hash = ""
        if self._checksum_file.exists():
            stored_hash = self._checksum_file.read_text(encoding="utf-8").strip()

        if (
            current_hash == stored_hash
            and self._sitepackages.exists()
            and any(self._sitepackages.iterdir())
        ):
            console.ok("Layer inalterada (checksum ok). Pulando instalação.")
            return True

        return self._do_install(current_hash)

    def _compute_hash(self) -> str:
        """Compute SHA-256 hash of requirements.txt."""
        hasher = hashlib.sha256()
        hasher.update(self._req_file.read_bytes())
        return hasher.hexdigest()

    def _do_install(self, current_hash: str) -> bool:
        """Run pip install into the layer directory."""
        console.info("Limpando dependências anteriores...")
        if self._sitepackages.exists():
            shutil.rmtree(self._sitepackages)
        self._sitepackages.mkdir(parents=True, exist_ok=True)

        console.info(f"Instalando dependências de '{self._req_file.name}'...")

        cmd = [
            sys.executable or self._python_bin,
            "-m", "pip", "install",
            "--platform", "manylinux2014_x86_64",
            "--implementation", "cp",
            "--python-version", self._python_version,
            "--only-binary=:all:",
            "-r", str(self._req_file),
            "-t", str(self._sitepackages),
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300,
            )
            if result.returncode != 0:
                console.fail("Falha ao instalar dependências da layer")
                if result.stderr:
                    console.console.print(f"  [dim]{result.stderr[:2000]}[/dim]")
                return False

            # Save checksum
            self._checksum_file.write_text(current_hash, encoding="utf-8")
            console.ok(f"Layer atualizada em '{self._sitepackages}'")
            return True

        except subprocess.TimeoutExpired:
            console.fail("Timeout ao instalar dependências (5 minutos)")
            return False
        except FileNotFoundError:
            console.fail(
                f"Python não encontrado ({sys.executable or self._python_bin}). "
                "Verifique PYTHON_BIN no .env."
            )
            return False
