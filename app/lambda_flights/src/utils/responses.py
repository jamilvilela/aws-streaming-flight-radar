"""
API Gateway Lambda response helpers.

API Gateway Proxy integration expects a specific response shape:
- statusCode: int
- headers: dict[str, str]
- body: str (JSON-serialized)
- isBase64Encoded: bool
"""
from __future__ import annotations

import json
from typing import Any, Optional


def build_response(
    status_code: int,
    body: Any,
    headers: Optional[dict[str, str]] = None,
) -> dict:
    base_headers = {
        "Content-Type": "application/json",
        "X-Content-Type-Options": "nosniff",
        "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    }
    if headers:
        base_headers.update(headers)
    return {
        "statusCode": status_code,
        "headers": base_headers,
        "body": json.dumps(body, separators=(",", ":")),
        "isBase64Encoded": False,
    }


def error_response(status_code: int, code: str, message: str, **extra) -> dict:
    payload = {"error": {"code": code, "message": message}}
    payload["error"].update(extra)
    return build_response(status_code, payload)
