"""IAM Roles verifier (for Lambda functions)."""

from __future__ import annotations

from ..ui import console
from .base import ResourceVerifier


class IAMVerifier(ResourceVerifier):
    """Verify IAM roles associated with project Lambda functions exist."""

    def verify(self) -> bool:
        console.step_header("10.3 — IAM Roles")
        ok = True

        lambdas = self._safe_query("lambda", "list_functions")
        if not lambdas or not lambdas.get("Functions"):
            return ok

        project_lambdas = [
            fn for fn in lambdas["Functions"]
            if fn["FunctionName"].startswith(self._config.project_name)
        ]

        if not project_lambdas:
            return ok

        for fn in project_lambdas:
            role_arn = fn.get("Role", "")
            role_name = role_arn.rsplit("/", 1)[-1] if role_arn else ""
            if not role_name:
                continue

            role = self._safe_query(
                "iam",
                "get_role",
                RoleName=role_name,
                error_msg=f"Erro ao descrever role {role_name}",
            )
            if role:
                trust = "unknown"
                try:
                    statements = (
                        role.get("Role", {})
                        .get("AssumeRolePolicyDocument", {})
                        .get("Statement", [])
                    )
                    if statements:
                        trust = str(
                            statements[0]
                            .get("Principal", {})
                            .get("Service", "unknown")
                        )
                except Exception:
                    pass
                console.ok(f"Role '{role_name}'", f"(assume: {trust})")

        return ok
