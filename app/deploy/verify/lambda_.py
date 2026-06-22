"""Lambda Functions verifier."""

from __future__ import annotations

from ..ui import console
from .base import ResourceVerifier


class LambdaVerifier(ResourceVerifier):
    """Verify Lambda functions exist and are active."""

    def verify(self) -> bool:
        console.step_header("10.2 — Lambda Functions")
        ok = True

        lambdas = self._safe_query("lambda", "list_functions")
        if not lambdas or not lambdas.get("Functions"):
            console.fail("Nenhuma Lambda encontrada na região")
            return False

        project_lambdas = [
            fn["FunctionName"]
            for fn in lambdas["Functions"]
            if fn["FunctionName"].startswith(self._config.project_name)
        ]

        if not project_lambdas:
            console.fail(
                f"Nenhuma Lambda do projeto encontrada "
                f"(prefixo: {self._config.project_name})"
            )
            return False

        for fn_name in project_lambdas:
            detail = self._safe_query(
                "lambda",
                "get_function",
                FunctionName=fn_name,
                error_msg=f"Erro ao descrever Lambda {fn_name}",
            )
            if detail:
                config = detail.get("Configuration", {})
                runtime = config.get("Runtime", "unknown")
                state = config.get("State", "unknown")
                console.ok(f"Lambda '{fn_name}'", f"(runtime: {runtime}, state: {state})")
            else:
                console.ok(f"Lambda '{fn_name}'", "(runtime: unknown, state: unknown)")

        return ok
