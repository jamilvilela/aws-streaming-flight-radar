"""
Dead Letter Queue (SQS) producer.

Receives records that failed validation (with the original payload + error
context) so they can be inspected, replayed, or alerted on. SQS batches up
to 10 messages per SendMessageBatch call (SQS limit).
"""
from __future__ import annotations

import json
import logging
import os
from typing import Iterable

import boto3
from botocore.exceptions import BotoCoreError, ClientError

logger = logging.getLogger(__name__)

_SQS_BATCH_LIMIT = 10
_client = None


def _get_client():
    global _client
    if _client is None:
        _client = boto3.client("sqs")
    return _client


def _chunk(items: list, limit: int) -> Iterable[list]:
    for i in range(0, len(items), limit):
        yield items[i : i + limit]


def _build_message(reason: str, payload, **context) -> dict:
    body = {
        "reason": reason,
        "received_at": context.get("received_at"),
        "request_id": context.get("request_id"),
        "api_key_id": context.get("api_key_id"),
        "source": context.get("source"),
        "payload": payload,
    }
    if "errors" in context:
        body["errors"] = context["errors"]
    return {
        "Id": str(context.get("seq", 0)),
        "MessageBody": json.dumps(body, separators=(",", ":")),
        "MessageAttributes": {
            "reason": {
                "DataType": "String",
                "StringValue": reason,
            },
        },
    }


def send_invalid(entries: list, queue_url: str, **context) -> int:
    """Persist records that failed validation. Returns count queued."""
    if not entries or not queue_url:
        return 0

    client = _get_client()
    queued = 0
    seq = 0

    for batch in _chunk(entries, _SQS_BATCH_LIMIT):
        messages = []
        for entry in batch:
            seq += 1
            messages.append(
                _build_message(
                    reason=entry.get("reason", "validation_error"),
                    payload=entry.get("payload"),
                    errors=entry.get("errors"),
                    seq=seq,
                    **context,
                )
            )
        try:
            response = client.send_message_batch(QueueUrl=queue_url, Entries=messages)
            failed = response.get("Failed", [])
            queued += len(messages) - len(failed)
            if failed:
                logger.error("SQS DLQ rejected %d messages: %s", len(failed), failed)
        except (ClientError, BotoCoreError):
            logger.exception("Failed to publish to DLQ; payload lost in this run")

    return queued
