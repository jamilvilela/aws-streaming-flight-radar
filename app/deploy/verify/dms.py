"""DMS Serverless verifier."""

from __future__ import annotations

from ..ui import console
from .base import ResourceVerifier


class DMSVerifier(ResourceVerifier):
    """Verify DMS Serverless replication configs exist for the project."""

    def verify(self) -> bool:
        console.step_header("10.7 — DMS Serverless")
        ok = True

        configs = self._safe_query(
            "dms",
            "describe_replication_configs",
            error_msg="Erro ao listar DMS replication configs",
        )
        if not configs or not configs.get("ReplicationConfigs"):
            console.warn("Nenhuma DMS Serverless config encontrada")
            return ok

        project_configs = [
            cfg for cfg in configs["ReplicationConfigs"]
            if self._config.project_name in cfg.get("ReplicationConfigIdentifier", "")
        ]

        if not project_configs:
            console.warn("Nenhuma DMS Serverless config do projeto encontrada")
            return ok

        console.ok(f"{len(project_configs)} DMS Serverless config(s):")
        for cfg in project_configs:
            cfg_id = cfg.get("ReplicationConfigIdentifier", "unknown")
            status = cfg.get("Status", "unknown")
            console.console.print(f"   - {cfg_id} (status: {status})")

        return ok
