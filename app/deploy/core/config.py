"""Configuration management — loads .env, tfvars, and CLI parameters."""

from __future__ import annotations

import configparser
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


@dataclass
class DeployConfig:
    """Central configuration for the deployment pipeline."""

    # Project info
    project_name: str = ""
    aws_region: str = "us-east-1"
    environment: str = "production"

    # Paths
    project_root: Path = field(default_factory=lambda: Path.cwd())
    infra_dir: Path = field(default_factory=lambda: Path.cwd() / "infra")
    tfvars_file: Path = field(default_factory=lambda: Path.cwd() / "infra" / "tfvars" / "terraform.tfvars")
    layer_root: Path = field(default_factory=lambda: Path.cwd() / "app" / "layers")
    requirements_file: Path = field(default_factory=lambda: Path.cwd() / "app" / "requirements.txt")

    # AWS credentials
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""
    aws_session_token: str = ""

    # RDS
    rds_admin_password: str = ""

    # Deployment flags
    skip_apply: bool = False
    no_verify: bool = False
    services: list[str] = field(default_factory=lambda: ["all"])

    # Terraform vars
    tf_vars: dict[str, str] = field(default_factory=dict)

    _loaded: bool = False

    @classmethod
    def from_env_and_args(
        cls,
        *,
        skip_apply: bool = False,
        no_verify: bool = False,
        services: Optional[list[str]] = None,
        project_root: Optional[Path] = None,
    ) -> "DeployConfig":
        """Build config from .env file, environment variables, and CLI args."""
        cfg = cls()
        cfg.skip_apply = skip_apply
        cfg.no_verify = no_verify
        if services:
            cfg.services = services
        if project_root:
            cfg.project_root = project_root
            cfg.infra_dir = project_root / "infra"
            cfg.tfvars_file = project_root / "infra" / "tfvars" / "terraform.tfvars"
            cfg.layer_root = project_root / "app" / "layers"
            cfg.requirements_file = project_root / "app" / "requirements.txt"

        cfg._load_dotenv()
        cfg._load_env_vars()
        cfg._load_tfvars()
        cfg._loaded = True
        return cfg

    # ── Private helpers ──────────────────────────────────────────────

    def _load_dotenv(self) -> None:
        """Load .env file from project root using dotenv conventions."""
        dotenv_path = self.project_root / ".env"
        if not dotenv_path.exists():
            return

        # Simple key=value parser (avoids python-dotenv dependency issues)
        with open(dotenv_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip().strip("\"'").strip()
                os.environ.setdefault(key, val)

    def _load_env_vars(self) -> None:
        """Read values from environment (already populated from .env or system)."""
        self.aws_region = os.environ.get("AWS_REGION", self.aws_region)
        self.aws_access_key_id = os.environ.get("AWS_ACCESS_KEY_ID", "")
        self.aws_secret_access_key = os.environ.get("AWS_SECRET_ACCESS_KEY", "")
        self.aws_session_token = os.environ.get("AWS_SESSION_TOKEN", "")
        self.rds_admin_password = os.environ.get("RDS_ADMIN_PASSWORD", "")
        self.environment = os.environ.get("ENVIRONMENT", self.environment)

        # TF_VAR_* overrides
        for key, val in os.environ.items():
            if key.startswith("TF_VAR_"):
                tf_key = key[7:].lower()
                self.tf_vars[tf_key] = val

        if "rds_admin_password" not in self.tf_vars and self.rds_admin_password:
            self.tf_vars["rds_admin_password"] = self.rds_admin_password

    def _load_tfvars(self) -> None:
        """Extract project_name and other vars from terraform.tfvars (HCL-like parsing)."""
        if not self.tfvars_file.exists():
            return

        with open(self.tfvars_file, encoding="utf-8") as f:
            content = f.read()

        # Simple regex-based parser for flat variables
        var_pattern = re.compile(r'^\s*(\w+)\s*=\s*"([^"]*)"\s*$', re.MULTILINE)
        for match in var_pattern.finditer(content):
            key = match.group(1)
            val = match.group(2)
            if key == "project_name" and not self.project_name:
                self.project_name = val
            elif key == "environment" and not self.environment:
                self.environment = val
            elif key == "aws_region" and self.aws_region == "us-east-1":
                self.aws_region = val

        # Also check TF_VAR_project_name from env
        if "project_name" in self.tf_vars:
            self.project_name = self.tf_vars["project_name"]

        # Fallback: try to read project_name from terraform.tfvars with flexible format
        if not self.project_name:
            for line in content.splitlines():
                stripped = line.strip()
                if stripped.startswith("project_name") and "=" in stripped:
                    val = stripped.split("=", 1)[1].strip().strip('"').strip("'")
                    self.project_name = val
                    break

    @property
    def dms_secret_name(self) -> str:
        """Name of the Secrets Manager secret for DMS Aurora credentials."""
        return f"{self.project_name}-dms-aurora-credentials"

    def validate(self) -> list[str]:
        """Validate configuration and return list of missing requirements."""
        errors: list[str] = []
        if not self.project_name:
            errors.append(
                "project_name não definido. Verifique .env (TF_VAR_project_name) "
                "ou infra/tfvars/terraform.tfvars"
            )
        if not self.aws_region:
            errors.append("aws_region não definido")
        if not self.infra_dir.exists():
            errors.append(f"Diretório infra/ não encontrado em {self.infra_dir}")
        if not self.tfvars_file.exists():
            errors.append(f"Arquivo tfvars não encontrado em {self.tfvars_file}")
        return errors
