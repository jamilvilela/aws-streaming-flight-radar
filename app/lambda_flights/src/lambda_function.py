"""
Lambda handler for the API Gateway edge of the flight-radar pipeline.

Flow:
1. Parse API Gateway Proxy event.
2. Normalize body (single object -> single-element batch).
3. Validate with Pydantic (per-record).
4. Apply partial-accept: invalid records go to SQS DLQ; valid go to Kinesis.
5. Return 207 Multi-Status when some records are rejected; 202 when all
   accepted; 400 when the whole payload is malformed.

Environment variables (injected by Terraform):
- KINESIS_STREAM         : target Kinesis Data Stream name
- DLQ_URL                : SQS queue URL for invalid records
- LOG_LEVEL              : "DEBUG" | "INFO" | "WARNING" (default INFO)
"""
from __future__ import annotations

import base64
import json
import logging
import os
import sys
import time
from typing import Any

from pydantic import ValidationError

from utils.dlq_producer import send_invalid
from utils.kinesis_producer import send as kinesis_send
from utils.models import FlightBatchIn, FlightStateIn, utc_now_iso
from utils.responses import build_response, error_response

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
if not logger.handlers:
    h = logging.StreamHandler(sys.stdout)
    h.setFormatter(
        logging.Formatter("%(asctime)s - %(levelname)s - %(name)s - %(message)s")
    )
    logger.addHandler(h)

# Lazy-resolved at first invocation (warm start reused)
_KINESIS_STREAM: str | None = None
_DLQ_URL: str | None = None


def _resolve_env() -> tuple[str, str]:
    global _KINESIS_STREAM, _DLQ_URL
    if _KINESIS_STREAM is None:
        _KINESIS_STREAM = os.environ.get("KINESIS_STREAM", "")
    if _DLQ_URL is None:
        _DLQ_URL = os.environ.get("DLQ_URL", "")
    return _KINESIS_STREAM, _DLQ_URL


def _parse_body(event: dict) -> Any:
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8", errors="replace")
    if not raw:
        return None
    return json.loads(raw)


def _extract_request_context(event: dict) -> dict:
    rc = event.get("requestContext", {}) or {}
    identity = rc.get("identity", {}) or {}
    return {
        "request_id": rc.get("requestId"),
        "api_key_id": identity.get("apiKeyId"),
        "source_ip": identity.get("sourceIp"),
        "user_agent": identity.get("userAgent"),
    }


def _validate_records(raw_records: list) -> tuple[list[FlightStateIn], list[dict]]:
    """Returns (valid_models, invalid_entries_for_dlq)."""
    valid: list[FlightStateIn] = []
    invalid: list[dict] = []

    for idx, raw in enumerate(raw_records):
        if not isinstance(raw, dict):
            invalid.append(
                {"reason": "type_error", "payload": raw, "errors": ["record must be an object"]}
            )
            continue
        try:
            valid.append(FlightStateIn.model_validate(raw))
        except ValidationError as exc:
            invalid.append(
                {
                    "reason": "validation_error",
                    "payload": raw,
                    "errors": [
                        {"loc": list(e["loc"]), "msg": e["msg"], "type": e["type"]}
                        for e in exc.errors()
                    ],
                }
            )

    return valid, invalid


def _to_kinesis_record(state: FlightStateIn) -> dict:
    data = state.model_dump(exclude_none=True)
    data["ingested_at"] = utc_now_iso()
    return {
        "Data": json.dumps(data, separators=(",", ":")),
        "PartitionKey": state.icao24,
    }


def lambda_handler(event: dict, context) -> dict:
    start = time.perf_counter()
    request_ctx = _extract_request_context(event)
    kinesis_stream, dlq_url = _resolve_env()

    if not kinesis_stream:
        logger.error("KINESIS_STREAM env var is not configured")
        return error_response(500, "misconfigured", "Stream not configured")

    try:
        body = _parse_body(event)
    except json.JSONDecodeError as exc:
        logger.warning("Malformed JSON body: %s", exc)
        return error_response(400, "invalid_json", "Request body is not valid JSON")

    if body is None:
        return error_response(400, "empty_body", "Request body is required")

    # Normalize: accept either {"states":[...]} or a single object or a bare list
    if isinstance(body, list):
        raw_records = body
        source = None
    elif isinstance(body, dict):
        if "states" in body and isinstance(body["states"], list):
            try:
                batch = FlightBatchIn.model_validate(body)
            except ValidationError as exc:
                return error_response(400, "invalid_batch", "Batch validation failed",
                                       details=exc.errors())
            raw_records = [s.model_dump() for s in batch.states]
            source = batch.source
        else:
            # Single object - treat as batch of 1
            raw_records = [body]
            source = body.get("source") if isinstance(body, dict) else None
    else:
        return error_response(400, "invalid_payload", "Body must be an object or array")

    if not raw_records:
        return error_response(400, "empty_batch", "At least one state record is required")

    if len(raw_records) > 500:
        return error_response(
            413, "payload_too_large",
            f"Batch size {len(raw_records)} exceeds the maximum of 500 records",
        )

    valid_models, invalid_entries = _validate_records(raw_records)

    sent = 0
    kinesis_failed: list[dict] = []
    if valid_models:
        records = [_to_kinesis_record(s) for s in valid_models]
        sent, _, failed = kinesis_send(records, kinesis_stream)
        kinesis_failed = failed

    # Persist any record that didn't make it to Kinesis to the DLQ
    dlq_payload = list(invalid_entries)
    for failed_record in kinesis_failed:
        # Kinesis `Data` is bytes; recover the original JSON
        try:
            payload = json.loads(failed_record.get("Data", b""))
        except (TypeError, ValueError):
            payload = failed_record.get("Data")
        dlq_payload.append({"reason": "kinesis_delivery_failed", "payload": payload})

    dlq_queued = 0
    if dlq_payload and dlq_url:
        dlq_queued = send_invalid(
            dlq_payload,
            dlq_url,
            received_at=utc_now_iso(),
            request_id=request_ctx.get("request_id"),
            api_key_id=request_ctx.get("api_key_id"),
            source=source,
        )

    accepted = sent
    rejected = len(raw_records) - accepted
    duration_ms = int((time.perf_counter() - start) * 1000)

    response_body = {
        "request_id": request_ctx.get("request_id"),
        "received": len(raw_records),
        "accepted": accepted,
        "rejected": rejected,
        "dlq_queued": dlq_queued,
        "kinesis_stream": kinesis_stream,
        "duration_ms": duration_ms,
    }

    if rejected == 0:
        status = 202
    elif accepted == 0:
        status = 400
    else:
        status = 207  # Multi-Status: partial accept

    if rejected:
        response_body["rejected_sample"] = [
            {"reason": e["reason"], "errors": e.get("errors")}
            for e in dlq_payload[:5]
        ]

    logger.info(
        "ingest request_id=%s received=%d accepted=%d rejected=%d dlq=%d duration_ms=%d",
        request_ctx.get("request_id"),
        len(raw_records),
        accepted,
        rejected,
        dlq_queued,
        duration_ms,
    )

    return build_response(status, response_body)
