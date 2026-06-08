"""
Lambda entry point for the API Gateway ingest path.

This file is intentionally minimal. Its only responsibilities are:
1. Configure the root logger (idempotent across warm invocations).
2. Lazily build a `FlightIngestHandler` from environment variables
   (constructed once per warm container).
3. Forward the AWS Lambda event to the handler.

All request logic, validation, Kinesis / DLQ dispatch, and structured
logging live in `utils.handler.FlightIngestHandler`. Keep this file thin
so it stays easy to audit (the entry point is what shows up in
CloudWatch as the Lambda's first log lines).
"""
from __future__ import annotations

import logging
import os
from typing import Optional

from utils.handler import FlightIngestHandler


def _configure_logger() -> None:
    """
    Configure the root logger.

    The AWS Lambda runtime installs its own handler on the root logger that
    forwards every record to CloudWatch with the standard
    `[LEVEL] <iso8601> <requestId> <message>` format. We must NOT add a second
    handler on top of that or each line is emitted twice (once with Lambda's
    format, once with ours). All we need to do is set the level from the
    `LOG_LEVEL` env var.
    """
    logging.getLogger().setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())


_configure_logger()

_handler: Optional[FlightIngestHandler] = None


def _get_handler() -> FlightIngestHandler:
    global _handler
    if _handler is None:
        _handler = FlightIngestHandler(
            kinesis_stream=os.environ.get("KINESIS_STREAM", ""),
            dlq_url=os.environ.get("DLQ_URL", ""),
        )
    return _handler


def lambda_handler(event: dict, context) -> dict:
    return _get_handler().handle(event, context)
