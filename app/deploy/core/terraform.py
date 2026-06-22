"""Terraform runner — init, validate, plan, apply, and output retrieval."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any, Optional

from ..ui import console


class TerraformRunner:
    """Manages Terraform lifecycle: init, validate, plan, apply, output."""

    def __init__(self, infra_dir: Path, tfvars_file: Path):
        self._infra_dir = infra_dir
        self._tfvars_file = tfvars_file
        self._plan_file = infra_dir / "tfplan"

    # ── Lifecycle ─────────────────────────────────────────────────────

    def init(self) -> bool:
        """Run terraform init. Returns True on success."""
        console.step_header("STEP 5 — terraform init")
        return self._run_cmd(["terraform", "init"], cwd=self._infra_dir)

    def validate(self) -> bool:
        """Run terraform validate. Returns True on success."""
        console.step_header("STEP 6 — terraform validate")
        return self._run_cmd(["terraform", "validate"], cwd=self._infra_dir)

    def plan(self) -> bool:
        """Run terraform plan -out=tfplan. Returns True on success."""
        console.step_header("STEP 7 — terraform plan")
        return self._run_cmd(
            [
                "terraform", "plan",
                f"-var-file={self._tfvars_file}",
                f"-out={self._plan_file.name}",
            ],
            cwd=self._infra_dir,
        )

    def apply(self) -> bool:
        """Run terraform apply with tfplan. Returns True on success."""
        console.step_header("STEP 8 — terraform apply")
        if not self._plan_file.exists():
            console.fail("tfplan não encontrado. Execute plan() primeiro.")
            return False
        return self._run_cmd(
            [
                "terraform", "apply",
                f"-var-file={self._tfvars_file}",
                "-auto-approve",
                self._plan_file.name,
            ],
            cwd=self._infra_dir,
        )

    # ── Outputs ───────────────────────────────────────────────────────

    def get_output(self, name: str, raw: bool = True) -> Optional[str]:
        """Get a single Terraform output value."""
        try:
            cmd = ["terraform", "output"]
            if raw:
                cmd.extend(["-raw", name])
            else:
                cmd.extend(["-json", name])
            result = subprocess.run(
                cmd,
                cwd=self._infra_dir,
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                return None
            val = result.stdout.strip()
            if raw:
                return val if val else None
            return json.loads(val) if val else None
        except (subprocess.TimeoutExpired, json.JSONDecodeError):
            return None

    def get_output_json(self, name: str) -> Any:
        """Get a Terraform output as parsed JSON."""
        return self.get_output(name, raw=False)

    def print_all_outputs(self) -> None:
        """Print all relevant Terraform outputs."""
        console.print_output_group(
            "Edge API (use these in the notebook .env)",
            [
                ("api_invoke_url", self.get_output("api_invoke_url") or "<missing>", False),
                ("api_id", self.get_output("api_id") or "<missing>", False),
                ("api_key_id", self.get_output("api_key_id") or "<missing>", False),
                ("api_key_value", self.get_output("api_key_value") or "<missing>", True),
            ],
        )
        console.print_output_group(
            "Lambda",
            [
                ("lambda_flights_function_name", self.get_output("lambda_flights_function_name") or "<missing>", False),
                ("lambda_flights_function_arn", self.get_output("lambda_flights_function_arn") or "<missing>", False),
                ("lambda_flights_iam_role_arn", self.get_output("lambda_flights_iam_role_arn") or "<missing>", False),
            ],
        )
        console.print_output_group(
            "Kinesis",
            [
                ("kinesis_stream_flights_info", str(self.get_output_json("kinesis_stream_flights_info") or "<missing>"), False),
            ],
        )
        console.print_output_group(
            "DLQ",
            [
                ("flights_dlq_arn", self.get_output("flights_dlq_arn") or "<missing>", False),
                ("flights_dlq_url", self.get_output("flights_dlq_url") or "<missing>", False),
            ],
        )
        console.print_output_group(
            "Aurora Serverless v2",
            [
                ("aurora_endpoint", self.get_output("aurora_endpoint") or "<missing>", False),
                ("aurora_reader_endpoint", self.get_output("aurora_reader_endpoint") or "<missing>", False),
                ("aurora_port", self.get_output("aurora_port") or "<missing>", False),
                ("aurora_db_name", self.get_output("aurora_db_name") or "<missing>", False),
                ("aurora_admin_username", self.get_output("aurora_admin_username") or "<missing>", True),
                ("aurora_security_group_id", self.get_output("aurora_security_group_id") or "<missing>", False),
                ("aurora_connection", self.get_output("aurora_connection") or "<missing>", True),
            ],
        )
        console.print_output_group(
            "DMS Serverless",
            [
                ("dms_replication_config_id", self.get_output("dms_replication_config_id") or "<missing>", False),
                ("dms_replication_config_arn", self.get_output("dms_replication_config_arn") or "<missing>", False),
                ("dms_source_endpoint_arn", self.get_output("dms_source_endpoint_arn") or "<missing>", False),
                ("dms_target_endpoint_arn", self.get_output("dms_target_endpoint_arn") or "<missing>", False),
                ("dms_replication_config_identifier", self.get_output("dms_replication_config_identifier") or "<missing>", False),
                ("dms_security_group_id", self.get_output("dms_security_group_id") or "<missing>", False),
            ],
        )

    # ── Internal ──────────────────────────────────────────────────────

    def _run_cmd(self, cmd: list[str], cwd: Optional[Path] = None) -> bool:
        """Run a shell command and stream output live."""
        cwd = cwd or Path.cwd()
        try:
            process = subprocess.Popen(
                cmd,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
            )
            if process.stdout:
                for line in iter(process.stdout.readline, ""):
                    if line:
                        console.console.print(f"  {line.rstrip()}")
            process.wait()
            if process.returncode == 0:
                console.ok("Concluído")
                return True
            console.fail(f"Comando falhou (exit code {process.returncode})")
            return False
        except FileNotFoundError:
            console.fail("terraform não encontrado. Instale o Terraform e tente novamente.")
            return False
