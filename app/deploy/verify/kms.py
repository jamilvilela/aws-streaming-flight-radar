"""KMS Keys verifier."""

from __future__ import annotations

from ..ui import console
from .base import ResourceVerifier


class KMSVerifier(ResourceVerifier):
    """Verify KMS keys exist for the project."""

    def verify(self) -> bool:
        console.step_header("10.8 — KMS Keys")
        ok = True

        keys = self._safe_query(
            "kms",
            "list_aliases",
            error_msg="Erro ao listar aliases KMS",
        )
        if not keys or not keys.get("Aliases"):
            console.warn("Nenhum alias KMS encontrado (pode ser intencional)")
            return ok

        project_aliases = [
            alias for alias in keys["Aliases"]
            if self._config.project_name in alias.get("AliasName", "")
        ]

        if not project_aliases:
            console.warn("Nenhum alias KMS do projeto encontrado (pode ser intencional)")
            return ok

        console.ok(f"{len(project_aliases)} KMS alias(es):")
        for alias in project_aliases:
            alias_name = alias.get("AliasName", "unknown")
            console.console.print(f"   - {alias_name}")

        return ok
