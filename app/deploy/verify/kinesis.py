"""Kinesis Data Streams verifier."""

from __future__ import annotations

from ..ui import console
from .base import ResourceVerifier


class KinesisVerifier(ResourceVerifier):
    """Verify Kinesis Data Streams exist and are active."""

    def verify(self) -> bool:
        console.step_header("10.1 — Kinesis Data Streams")
        ok = True

        streams = self._safe_query("kinesis", "list_streams")
        if not streams or not streams.get("StreamNames"):
            console.fail("Nenhum Kinesis stream encontrado na região")
            return False

        project_streams = [
            s for s in streams["StreamNames"]
            if s.startswith(self._config.project_name)
        ]

        if not project_streams:
            console.fail(
                f"Nenhum Kinesis stream do projeto encontrado "
                f"(prefixo: {self._config.project_name})"
            )
            console.info(f"Streams disponíveis: {', '.join(streams['StreamNames'])}")
            return False

        for stream_name in project_streams:
            status = self._safe_query(
                "kinesis",
                "describe_stream_summary",
                StreamName=stream_name,
                error_msg=f"Erro ao descrever stream {stream_name}",
            )
            stream_status = (
                status.get("StreamDescriptionSummary", {}).get("StreamStatus", "unknown")
                if status
                else "unknown"
            )
            console.ok(f"Stream '{stream_name}'", f"(status: {stream_status})")

        return ok
