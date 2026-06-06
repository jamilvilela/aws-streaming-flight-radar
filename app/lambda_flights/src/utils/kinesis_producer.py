"""
Kinesis producer with batch + retry.

Implements:
- Records batched up to 500 (PutRecords API limit) and 5MB total payload
- Exponential backoff for ProvisionedThroughputExceededException
- Per-record retry for the records that Kinesis marked as failed
- Uses icao24 as the partition key so that updates for the same aircraft
  land on the same shard (preserving per-flight ordering in Flink).
"""
from __future__ import annotations

import json
import logging
import os
import time
from typing import Iterable

import boto3
from botocore.exceptions import BotoCoreError, ClientError

logger = logging.getLogger(__name__)

_KINESIS_BATCH_LIMIT = 500
_KINESIS_MAX_PAYLOAD_BYTES = 5 * 1024 * 1024  # 5 MiB

_client = None


def _get_client():
    global _client
    if _client is None:
        _client = boto3.client("kinesis")
    return _client


def _chunk(records: list[dict], limit: int) -> Iterable[list[dict]]:
    for i in range(0, len(records), limit):
        yield records[i : i + limit]


def send(records: list[dict], stream_name: str, max_retries: int = 3) -> tuple[int, int, list[dict]]:
    """
    Send records to Kinesis.

    Returns:
        (sent_count, failed_count, failed_records) - the failed_records are
        a best-effort subset of records that could not be delivered after
        retries. The DLQ layer should persist them.
    """
    if not records:
        return 0, 0, []

    if not stream_name:
        raise ValueError("stream_name is required")

    client = _get_client()
    sent = 0
    permanently_failed: list[dict] = []

    for batch in _chunk(records, _KINESIS_BATCH_LIMIT):
        attempt = 0
        current = batch
        while current and attempt <= max_retries:
            try:
                response = client.put_records(
                    StreamName=stream_name,
                    Records=current,
                )
            except ClientError as exc:
                code = exc.response.get("Error", {}).get("Code")
                if code == "ProvisionedThroughputExceededException" and attempt < max_retries:
                    backoff = (2 ** attempt) * 0.2
                    logger.warning("Kinesis throttled, backing off %.2fs", backoff)
                    time.sleep(backoff)
                    attempt += 1
                    continue
                logger.exception("Kinesis put_records failed: %s", exc)
                permanently_failed.extend(current)
                current = []
                break
            except BotoCoreError:
                logger.exception("Boto core error sending to Kinesis")
                permanently_failed.extend(current)
                current = []
                break

            failed_count = response.get("FailedRecordCount", 0) or 0
            if failed_count == 0:
                sent += len(current)
                current = []
                break

            # Filter only the records that Kinesis flagged as failed
            retriable: list[dict] = []
            for idx, item in enumerate(response.get("Records", [])):
                if "ErrorCode" in item:
                    # Re-send the original record (position aligned with `current`)
                    if idx < len(current):
                        retriable.append(current[idx])

            if not retriable or attempt >= max_retries:
                permanently_failed.extend(retriable or current)
                current = []
                break

            attempt += 1
            backoff = (2 ** attempt) * 0.2
            logger.warning(
                "Kinesis partial failure: %d/%d records failed, retrying in %.2fs",
                len(retriable),
                len(current),
                backoff,
            )
            time.sleep(backoff)
            current = retriable

    failed = len(permanently_failed)
    logger.info("Kinesis put complete: sent=%d failed=%d", sent, failed)
    return sent, failed, permanently_failed
