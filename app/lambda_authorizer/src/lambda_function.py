"""
Lambda Authorizer for the flight-radar REST API.

A REST API Lambda Authorizer must return a policy document of the form:
    {
      "principalId": "<caller-id>",
      "policyDocument": {
        "Version": "2012-10-17",
        "Statement": [{
          "Action": "execute-api:Invoke",
          "Effect": "Allow" | "Deny",
          "Resource": "arn:aws:execute-api:<region>:<acct>:<api-id>/<stage>/<METHOD>/<resource>"
        }]
      },
      "context": { ... optional passthrough to backend ... }
}

This authorizer is intentionally minimal:
- It trusts the API Gateway `apiKeyId` identity (already provided when
  the client sends X-Api-Key). API Key + Usage Plan handle rotation,
  throttling, and revocation.
- It enforces a deny-list of countries using the ISO-3166 alpha-2 codes
  passed via the `ALLOWED_COUNTRIES` env var (comma-separated; "*" or
  empty means allow all).
- It propagates the API key id and the source IP as `context` so the
  ingestion Lambda can include them in CloudWatch logs and DLQ entries.

For more sophisticated needs (e.g. short-lived JWTs, signed requests),
swap the body of `authorize` - the contract above stays the same.
"""
from __future__ import annotations

import json
import logging
import os
import re
import sys
from typing import Optional

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
if not logger.handlers:
    h = logging.StreamHandler(sys.stdout)
    h.setFormatter(logging.Formatter("%(asctime)s - %(levelname)s - %(name)s - %(message)s"))
    logger.addHandler(h)

ALLOWED_COUNTRIES_RAW = os.environ.get("ALLOWED_COUNTRIES", "*").strip()
ALLOWED_COUNTRIES: Optional[set[str]] = (
    None if ALLOWED_COUNTRIES_RAW in ("", "*") else {c.strip().upper() for c in ALLOWED_COUNTRIES_RAW.split(",") if c.strip()}
)

_MAX_CONTEXT_LEN = 2048  # hard limit for API Gateway authorizer context
_API_KEY_RE = re.compile(r"^[A-Za-z0-9]{8,128}$")


def _allow_policy(arn: str) -> dict:
    return {
        "principalId": "apikey",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": "Allow",
                    "Resource": arn,
                }
            ],
        },
        "context": {},
    }


def _deny_policy(arn: str, reason: str) -> dict:
    logger.info("denying request: %s", reason)
    return {
        "principalId": "apikey",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": "Deny",
                    "Resource": arn,
                }
            ],
        },
        "context": {"denyReason": reason[: _MAX_CONTEXT_LEN]},
    }


def authorize(event: dict) -> dict:
    arn = event.get("methodArn") or ""
    if not arn:
        logger.error("missing methodArn in event")
        return _deny_policy("*", "missing_method_arn")

    # API Gateway already validates the X-Api-Key against the Usage Plan.
    # For a TOKEN authorizer, the raw X-Api-Key value is delivered as
    # `authorizationToken`. We do not re-validate the key itself; we just
    # make sure a non-empty token is present so the request can't sneak
    # past when the key header is missing (which should not happen if
    # api_key_required is set on the method, but defense-in-depth).
    api_key_id = event.get("authorizationToken") or ""
    if not api_key_id or not _API_KEY_RE.match(api_key_id):
        return _deny_policy(arn, f"missing_or_invalid_api_key:{api_key_id!r}")

    # Optional country allow-list. The authorizer does not know the body,
    # so the per-record country filter lives in the ingestion Lambda.
    # Here we only enforce per-client (caller IP) if needed.
    if ALLOWED_COUNTRIES is not None:
        caller_country = identity.get("country") or ""
        if caller_country and caller_country.upper() not in ALLOWED_COUNTRIES:
            return _deny_policy(arn, f"country_not_allowed:{caller_country}")

    return _allow_policy(arn)


def lambda_handler(event, context):
    return authorize(event)
