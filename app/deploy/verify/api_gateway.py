"""API Gateway verifier — REST APIs, stages, API keys, and usage plans."""

from __future__ import annotations

from ..ui import console
from .base import ResourceVerifier


class APIGatewayVerifier(ResourceVerifier):
    """Verify API Gateway REST API, stages, API keys, and usage plans."""

    def verify(self) -> bool:
        console.step_header("10.5 — API Gateway (REST API)")
        ok = True

        apis = self._safe_query("apigateway", "get_rest_apis")
        if not apis or not apis.get("items"):
            console.fail("Nenhum API Gateway encontrado")
            return False

        project_apis = [
            api for api in apis["items"]
            if self._config.project_name in api.get("name", "")
        ]

        if not project_apis:
            console.fail(
                f"API Gateway do projeto não encontrado "
                f"(nome esperado contém: {self._config.project_name})"
            )
            return False

        for api in project_apis:
            api_id = api["id"]
            api_name = api.get("name", "unknown")
            console.ok(f"API '{api_name}'", f"(id: {api_id})")

            # Stages
            stages = self._safe_query(
                "apigateway",
                "get_stages",
                restApiId=api_id,
                error_msg=f"Erro ao listar stages da API {api_id}",
            )
            if stages and stages.get("item"):
                for stage in stages["item"]:
                    stage_name = stage.get("stageName", "")
                    invoke_url = (
                        f"https://{api_id}.execute-api."
                        f"{self._config.aws_region}.amazonaws.com/{stage_name}"
                    )
                    console.ok(f"  Stage: {stage_name}  →  {invoke_url}")

            # API Keys
            keys = self._safe_query(
                "apigateway",
                "get_api_keys",
                restApiId=api_id,
                error_msg=f"Erro ao listar API keys da API {api_id}",
            )
            if keys and keys.get("items"):
                for key_item in keys["items"]:
                    kid = key_item.get("id", "")
                    kname = key_item.get("name", "")
                    kenabled = key_item.get("enabled", False)
                    key_value = self._safe_query(
                        "apigateway",
                        "get_api_key",
                        apiKey=kid,
                        includeValue=True,
                        error_msg=f"Erro ao obter API key {kid}",
                    )
                    value = (
                        (key_value.get("value", "")[:8] + "...")
                        if key_value
                        else "unknown"
                    )
                    console.ok(
                        f"  API Key: {kname}",
                        f"(id: {kid}, enabled: {kenabled}, value: {value})",
                    )

            # Usage Plans
            plans = self._safe_query(
                "apigateway",
                "get_usage_plans",
                error_msg="Erro ao listar usage plans",
            )
            if plans and plans.get("items"):
                for plan in plans["items"]:
                    pid = plan.get("id", "")
                    pname = plan.get("name", "")
                    throttle = plan.get("throttle", {})
                    quota = plan.get("quota", {})
                    p_rate = throttle.get("rateLimit", "?")
                    p_burst = throttle.get("burstLimit", "?")
                    p_quota = quota.get("limit", "none")
                    p_period = quota.get("period", "none")
                    console.ok(
                        f"  Usage Plan: {pname}",
                        f"(rate={p_rate}/s, burst={p_burst}, "
                        f"quota={p_quota}/{p_period})",
                    )

        return ok
