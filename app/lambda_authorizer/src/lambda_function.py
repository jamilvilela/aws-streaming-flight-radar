"""
Lambda entry point for the API Gateway TOKEN authorizer.

This file is intentionally minimal. Its only responsibilities are:
1. Configure the root logger (idempotent across warm invocations).
2. Lazily build an `AuthorizerHandler` from environment variables
   (constructed once per warm container).
3. Forward the AWS Lambda event to the handler.

All authorization logic and structured logging live in
`utils.handler.AuthorizerHandler`. Keep this file thin.
"""
from __future__ import annotations

import logging
import os
from typing import Optional, Set

from utils.handler import AuthorizerHandler


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

_handler: Optional[AuthorizerHandler] = None


def _get_handler() -> AuthorizerHandler:
    global _handler
    if _handler is None:
        raw = os.environ.get("ALLOWED_COUNTRIES", "*").strip()
        if raw in ("", "*"):
            allowed: Optional[Set[str]] = None
        else:
            allowed = {c.strip().upper() for c in raw.split(",") if c.strip()}
        _handler = AuthorizerHandler(allowed_countries=allowed)
    return _handler


def lambda_handler(event, context):
    return _get_handler().handle(event, context)
