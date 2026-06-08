"""
Encapsulated request handler for the API Gateway -> Kinesis ingest path.

`FlightIngestHandler` owns the full per-request pipeline. The Lambda entry
point (`lambda_function.lambda_handler`) should only resolve the
environment, instantiate one handler, and forward the call to `handle()`.

Pipeline (each step is a private method and emits its own log line):
    1. _parse_body        - decode API Gateway proxy body (base64 aware)
    2. _normalize         - accept {states:[...]} | single object | bare list
    3. _validate_records  - Pydantic per-record; invalids go to DLQ
    4. _send_to_kinesis   - batch + retry; failures go to DLQ
    5. _persist_dlq       - any record that didn't reach Kinesis is queued
    6. _build_response    - 202 / 207 / 400 / 413

Logging strategy:
- One INFO line per pipeline step (dotted prefix: `ingest.<step>`) so
  CloudWatch Insights can `parse @message` and group by stage.
- DEBUG lines for payload previews (truncated) and per-record errors.
- A top-level try/except in `handle` converts any unexpected exception
  to a 500 with a logged traceback; the Lambda never crashes silently.
"""
from __future__ import annotations

import base64
import json
import logging
import time
from typing import Any, Optional

from pydantic import ValidationError

from utils.dlq_producer import send_invalid
from utils.kinesis_producer import send as kinesis_send
from utils.models import FlightBatchIn, FlightStateIn, utc_now_iso
from utils.responses import build_response, error_response

logger = logging.getLogger(__name__)


class FlightIngestHandler:
    """End-to-end handler for one ingest request."""

    MAX_BATCH = 500
    LOG_PAYLOAD_PREVIEW_BYTES = 256  # truncated preview of bodies / records in DEBUG

    def __init__(self, kinesis_stream: str, dlq_url: str):
        self._kinesis_stream = kinesis_stream
        self._dlq_url = dlq_url

    # ---- public entry point -------------------------------------------------
    def handle(self, event: dict, context) -> dict:
        start = time.perf_counter()
        ctx = self._extract_request_context(event)
        log = logger.getChild("handle")
        log.info(
            "ingest.start request_id=%s api_key_id=%s source_ip=%s ua=%s",
            ctx.get("request_id"),
            ctx.get("api_key_id"),
            ctx.get("source_ip"),
            ctx.get("user_agent"),
        )
        try:
            response = self._dispatch(event, ctx, start)
        except Exception:
            log.exception("ingest.unhandled_error request_id=%s", ctx.get("request_id"))
            return error_response(500, "internal", "Internal error")
        log.info(
            "ingest.end request_id=%s status=%s duration_ms=%d",
            ctx.get("request_id"),
            response.get("statusCode"),
            int((time.perf_counter() - start) * 1000),
        )
        return response

    # ---- pipeline -----------------------------------------------------------
    def _dispatch(self, event: dict, ctx: dict, start: float) -> dict:
        log = logger.getChild("dispatch")

        if not self._kinesis_stream:
            log.error("ingest.misconfigured reason=kinesis_stream_missing")
            return error_response(500, "misconfigured", "Stream not configured")

        try:
            body = self._parse_body(event)
        except json.JSONDecodeError as exc:
            log.warning("ingest.body.invalid_json err=%s", exc)
            return error_response(400, "invalid_json", "Request body is not valid JSON")

        if body is None:
            log.warning("ingest.body.empty request_id=%s", ctx.get("request_id"))
            return error_response(400, "empty_body", "Request body is required")

        log.debug("ingest.body.parsed preview=%r", _truncate(body, self.LOG_PAYLOAD_PREVIEW_BYTES))

        normalized = self._normalize(body)
        if isinstance(normalized, dict) and "statusCode" in normalized:
            return normalized
        raw_records, source = normalized  # type: ignore[misc]

        if not raw_records:
            return error_response(400, "empty_batch", "At least one state record is required")
        if len(raw_records) > self.MAX_BATCH:
            log.warning("ingest.batch.too_large count=%d", len(raw_records))
            return error_response(
                413, "payload_too_large",
                f"Batch size {len(raw_records)} exceeds the maximum of {self.MAX_BATCH} records",
            )

        log.info("ingest.batch.received count=%d source=%s", len(raw_records), source)

        valid_models, invalid_entries = self._validate_records(raw_records)
        log.info(
            "ingest.validate.valid=%d invalid=%d",
            len(valid_models), len(invalid_entries),
        )
        if invalid_entries:
            log.debug("ingest.validate.errors sample=%s",
                      _truncate(invalid_entries[:3], self.LOG_PAYLOAD_PREVIEW_BYTES))

        sent, kinesis_failed = self._send_to_kinesis(valid_models)
        log.info("ingest.kinesis.sent=%d failed=%d", sent, len(kinesis_failed))

        dlq_payload = list(invalid_entries)
        for failed_record in kinesis_failed:
            payload = self._decode_kinesis_data(failed_record)
            dlq_payload.append({"reason": "kinesis_delivery_failed", "payload": payload})
        dlq_queued = self._persist_dlq(dlq_payload, ctx, source)
        log.info("ingest.dlq.queued=%d", dlq_queued)

        return self._build_response(ctx, len(raw_records), sent, dlq_queued, dlq_payload, start)

    # ---- pipeline steps (private) ------------------------------------------
    def _parse_body(self, event: dict) -> Any:
        raw = event.get("body") or ""
        if event.get("isBase64Encoded"):
            raw = base64.b64decode(raw).decode("utf-8", errors="replace")
        if not raw:
            return None
        return json.loads(raw)

    def _normalize(self, body: Any):
        if isinstance(body, list):
            return body, None
        if isinstance(body, dict):
            if "states" in body and isinstance(body["states"], list):
                try:
                    batch = FlightBatchIn.model_validate(body)
                except ValidationError as exc:
                    logger.getChild("normalize").warning(
                        "ingest.batch.invalid err_count=%d", len(exc.errors()),
                    )
                    return error_response(
                        400, "invalid_batch", "Batch validation failed",
                        details=exc.errors(),
                    )
                return [s.model_dump() for s in batch.states], batch.source
            return [body], body.get("source") if isinstance(body, dict) else None
        return error_response(400, "invalid_payload", "Body must be an object or array")

    def _validate_records(self, raw_records: list) -> tuple[list[FlightStateIn], list[dict]]:
        valid: list[FlightStateIn] = []
        invalid: list[dict] = []
        for idx, raw in enumerate(raw_records):
            if not isinstance(raw, dict):
                invalid.append({
                    "reason": "type_error",
                    "payload": raw,
                    "errors": ["record must be an object"],
                })
                continue
            try:
                valid.append(FlightStateIn.model_validate(raw))
            except ValidationError as exc:
                invalid.append({
                    "reason": "validation_error",
                    "payload": raw,
                    "errors": [
                        {"loc": list(e["loc"]), "msg": e["msg"], "type": e["type"]}
                        for e in exc.errors()
                    ],
                })
        return valid, invalid

    def _send_to_kinesis(self, valid_models: list[FlightStateIn]) -> tuple[int, list[dict]]:
        if not valid_models:
            return 0, []
        records = [self._to_kinesis_record(s) for s in valid_models]
        sent, _failed_count, failed = kinesis_send(records, self._kinesis_stream)
        return sent, failed

    def _persist_dlq(self, dlq_payload: list, ctx: dict, source: Optional[str]) -> int:
        if not dlq_payload or not self._dlq_url:
            return 0
        return send_invalid(
            dlq_payload,
            self._dlq_url,
            received_at=utc_now_iso(),
            request_id=ctx.get("request_id"),
            api_key_id=ctx.get("api_key_id"),
            source=source,
        )

    def _to_kinesis_record(self, state: FlightStateIn) -> dict:
        data = state.model_dump(exclude_none=True)
        data["ingested_at"] = utc_now_iso()
        return {
            "Data": json.dumps(data, separators=(",", ":")),
            "PartitionKey": state.icao24,
        }

    @staticmethod
    def _decode_kinesis_data(failed_record: dict):
        try:
            return json.loads(failed_record.get("Data", b""))
        except (TypeError, ValueError):
            return failed_record.get("Data")

    @staticmethod
    def _extract_request_context(event: dict) -> dict:
        rc = event.get("requestContext", {}) or {}
        identity = rc.get("identity", {}) or {}
        return {
            "request_id": rc.get("requestId"),
            "api_key_id": identity.get("apiKeyId"),
            "source_ip": identity.get("sourceIp"),
            "user_agent": identity.get("userAgent"),
        }

    def _build_response(
        self,
        ctx: dict,
        received: int,
        accepted: int,
        dlq_queued: int,
        dlq_payload: list,
        start: float,
    ) -> dict:
        rejected = received - accepted
        duration_ms = int((time.perf_counter() - start) * 1000)

        if rejected == 0:
            status = 202
        elif accepted == 0:
            status = 400
        else:
            status = 207  # Multi-Status: partial accept

        body = {
            "request_id": ctx.get("request_id"),
            "received": received,
            "accepted": accepted,
            "rejected": rejected,
            "dlq_queued": dlq_queued,
            "kinesis_stream": self._kinesis_stream,
            "duration_ms": duration_ms,
        }
        if rejected:
            body["rejected_sample"] = [
                {"reason": e["reason"], "errors": e.get("errors")}
                for e in dlq_payload[:5]
            ]
        return build_response(status, body)


def _truncate(obj: Any, max_bytes: int) -> str:
    """Stringify and cap size, useful for DEBUG payload previews."""
    try:
        s = json.dumps(obj, default=str, separators=(",", ":"))
    except (TypeError, ValueError):
        s = repr(obj)
    if len(s) <= max_bytes:
        return s
    return s[:max_bytes] + f"...<+{len(s) - max_bytes}B>"
