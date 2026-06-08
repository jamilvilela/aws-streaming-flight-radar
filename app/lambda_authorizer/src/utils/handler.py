"""
Encapsulated handler for the API Gateway TOKEN Lambda Authorizer.

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

`AuthorizerHandler` owns the full authorization decision for one event.
The Lambda entry point (`lambda_function.lambda_handler`) should only
resolve the environment, instantiate one handler, and forward the call.

Authorization strategy:
- For TOKEN authorizers the raw X-Api-Key value arrives as
  `event["authorizationToken"]`. API Gateway already validates the key
  against the Usage Plan; we apply defense-in-depth by checking the
  shape (length/charset) of the token.
- Optional `ALLOWED_COUNTRIES` filter (ISO-3166 alpha-2, comma-separated,
  "*" or empty = allow all) is read from the request context identity.
- The token (or a truncated form) is propagated to the backend via
  `context.apiKeyId` so the ingestion Lambda can include it in logs and
  DLQ entries.
"""
from __future__ import annotations

import logging
import re
from typing import Optional

logger = logging.getLogger(__name__)


class AuthorizerHandler:
    """End-to-end authorizer for one event."""

    _MAX_CONTEXT_LEN = 2048  # hard limit for API Gateway authorizer context
    _API_KEY_RE = re.compile(r"^[A-Za-z0-9]{8,128}$")
    _API_KEY_REDACT_LEN = 8  # keep this many chars in DEBUG logs

    def __init__(self, allowed_countries: Optional[set[str]] = None):
        self._allowed_countries = allowed_countries

    def handle(self, event: dict, context) -> dict:
        arn = (event.get("methodArn") or "").strip()
        log = logger.getChild("handle")
        log.info("authorizer.start method_arn=%s", arn or "<missing>")

        if not arn:
            log.error("authorizer.error reason=missing_method_arn")
            return self._deny_policy("*", "missing_method_arn")

        token = (event.get("authorizationToken") or "").strip()
        if not token or not self._API_KEY_RE.match(token):
            log.info("authorizer.deny reason=invalid_api_key token_len=%d", len(token))
            return self._deny_policy(arn, f"missing_or_invalid_api_key:{token!r}")

        if self._allowed_countries is not None:
            identity = (event.get("requestContext", {}) or {}).get("identity", {}) or {}
            caller_country = (identity.get("country") or "").upper()
            if caller_country and caller_country not in self._allowed_countries:
                log.info(
                    "authorizer.deny reason=country_not_allowed country=%s",
                    caller_country,
                )
                return self._deny_policy(arn, f"country_not_allowed:{caller_country}")

        log.info(
            "authorizer.allow api_key_id=%s method_arn=%s",
            self._redact_token(token),
            arn,
        )
        return self._allow_policy(arn, token)

    # ---- policy builders ---------------------------------------------------
    @staticmethod
    def _allow_policy(arn: str, api_key_id: str) -> dict:
        return {
            "principalId": api_key_id[:32],
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
            "context": {
                "apiKeyId": api_key_id[:64],
            },
        }

    @staticmethod
    def _deny_policy(arn: str, reason: str) -> dict:
        logger.info("authorizer.deny reason=%s", reason)
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
            "context": {"denyReason": reason[: AuthorizerHandler._MAX_CONTEXT_LEN]},
        }

    @classmethod
    def _redact_token(cls, token: str) -> str:
        if len(token) <= cls._API_KEY_REDACT_LEN:
            return "***"
        return token[: cls._API_KEY_REDACT_LEN] + "***"
