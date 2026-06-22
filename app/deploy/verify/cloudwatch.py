"""CloudWatch Log Groups verifier."""

from __future__ import annotations

from ..ui import console
from .base import ResourceVerifier


class CloudWatchVerifier(ResourceVerifier):
    """Verify CloudWatch Log Groups for Lambda and API Gateway exist."""

    def verify(self) -> bool:
        console.step_header("10.6 — CloudWatch Log Groups")
        ok = True

        # Lambda log groups
        lambda_logs = self._safe_query(
            "logs",
            "describe_log_groups",
            logGroupNamePrefix=f"/aws/lambda/{self._config.project_name}",
            error_msg="Erro ao listar log groups Lambda",
        )
        if lambda_logs and lambda_logs.get("logGroups"):
            log_groups = lambda_logs["logGroups"]
            console.ok(f"{len(log_groups)} Lambda log group(s):")
            for lg in log_groups:
                console.console.print(f"   - {lg['logGroupName']}")
        else:
            console.warn(
                f"Nenhum log group /aws/lambda/{self._config.project_name}* encontrado"
            )

        # API Gateway log groups
        apigw_logs = self._safe_query(
            "logs",
            "describe_log_groups",
            logGroupNamePrefix=f"/aws/apigateway/{self._config.project_name}",
            error_msg="Erro ao listar log groups API Gateway",
        )
        if apigw_logs and apigw_logs.get("logGroups"):
            log_groups = apigw_logs["logGroups"]
            console.ok(f"{len(log_groups)} API Gateway log group(s):")
            for lg in log_groups:
                console.console.print(f"   - {lg['logGroupName']}")

        return ok
