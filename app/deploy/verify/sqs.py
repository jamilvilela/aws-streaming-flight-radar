"""SQS Dead Letter Queue verifier."""

from __future__ import annotations

from ..ui import console
from .base import ResourceVerifier


class SQSVerifier(ResourceVerifier):
    """Verify SQS DLQ exists for the project."""

    def verify(self) -> bool:
        console.step_header("10.4 — SQS Dead Letter Queues")
        ok = True

        queues = self._safe_query("sqs", "list_queues")
        if not queues or not queues.get("QueueUrls"):
            console.fail("Nenhuma fila SQS encontrada")
            return False

        dlq_urls = [
            url for url in queues["QueueUrls"]
            if self._config.project_name in url and "flights-dlq" in url
        ]

        if not dlq_urls:
            console.fail(
                f"DLQ do projeto não encontrada "
                f"(esperado: {self._config.project_name}*flights-dlq)"
            )
            return False

        for url in dlq_urls:
            console.ok(f"DLQ: {url}")

        return ok
