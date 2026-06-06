"""
HTTP client for the project's edge API Gateway.

Two transport strategies are exposed:

- send_states_to_api_batch  : one POST to /flights/batch with the full list.
                             Cheaper (one request, less Lambda cold-start
                             pressure) but failure on a single record causes
                             partial accept to be hidden behind a 207.

- send_states_to_api_single : one POST to /flights per state.
                             Higher HTTP overhead but easier to map each
                             state to its own response (good for debugging
                             or low-volume feeds).

Both methods return a small dict describing the result so the caller can
log/aggregate however it wants.
"""
from __future__ import annotations

import logging
import os
import time
from typing import Any, Iterable

import requests
from requests import Response
from requests.exceptions import RequestException

logger = logging.getLogger(__name__)


# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

def _cfg(name: str, default: str | None = None, *, cast=str) -> Any:
    raw = os.environ.get(name, default)
    if raw is None:
        return None
    try:
        return cast(raw)
    except (TypeError, ValueError):
        logger.warning("Invalid value for env %s=%r, using default", name, raw)
        return default


API_BASE_URL: str = (_cfg("API_BASE_URL", "") or "").rstrip("/")
API_KEY: str = _cfg("API_KEY", "")
SOURCE_TAG: str = _cfg("SOURCE_TAG", "notebook")
REQUEST_TIMEOUT: int = _cfg("REQUEST_TIMEOUT_SECONDS", "15", cast=int)
MAX_RETRIES: int = _cfg("MAX_RETRIES", "3", cast=int)
BATCH_CHUNK_SIZE: int = _cfg("BATCH_CHUNK_SIZE", "500", cast=int)

BATCH_PATH = "/flights/batch"
SINGLE_PATH = "/flights"


# --------------------------------------------------------------------------- #
# Internal helpers
# --------------------------------------------------------------------------- #

def _validate_config() -> None:
    if not API_BASE_URL:
        raise RuntimeError("API_BASE_URL is not set; check your .env file")
    if not API_KEY or API_KEY == "REPLACE_ME_WITH_TERRAFORM_OUTPUT_API_KEY_VALUE":
        raise RuntimeError(
            "API_KEY is not set (or still the placeholder); "
            "run `terraform output -raw api_key_value` and update .env"
        )


def _headers() -> dict[str, str]:
    return {
        "X-Api-Key": API_KEY,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "get_flights_data_notebook/1.0",
    }


def _post_with_retry(path: str, body: dict) -> tuple[Response | None, dict[str, Any]]:
    """
    POST a JSON body to the API with bounded exponential backoff for
    transient errors (5xx, network). Returns (response, meta) where `meta`
    carries timing and attempt info.
    """
    _validate_config()
    url = f"{API_BASE_URL}{path}"
    meta: dict[str, Any] = {"url": url, "attempts": 0, "elapsed_ms": 0}
    start = time.perf_counter()

    last_exc: Exception | None = None
    for attempt in range(1, MAX_RETRIES + 1):
        meta["attempts"] = attempt
        try:
            resp = requests.post(url, headers=_headers(), json=body, timeout=REQUEST_TIMEOUT)
            meta["elapsed_ms"] = int((time.perf_counter() - start) * 1000)
            meta["status_code"] = resp.status_code
            return resp, meta
        except RequestException as exc:
            last_exc = exc
            logger.warning(
                "POST %s failed (attempt %d/%d): %s", path, attempt, MAX_RETRIES, exc
            )
            if attempt < MAX_RETRIES:
                time.sleep(min(2 ** attempt, 30))

    meta["elapsed_ms"] = int((time.perf_counter() - start) * 1000)
    meta["error"] = str(last_exc) if last_exc else "unknown"
    return None, meta


def _summarize_response(resp: Response | None) -> dict[str, Any]:
    if resp is None:
        return {"ok": False, "reason": "network_error"}
    try:
        body = resp.json()
    except ValueError:
        body = {"raw": resp.text[:500]}

    return {
        "ok": resp.ok,
        "status_code": resp.status_code,
        "body": body,
    }


def _iter_chunks(items: list, size: int) -> Iterable[list]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #

def send_states_to_api_batch(
    states_payload: list[dict],
    *,
    source: str | None = None,
    chunk_size: int = BATCH_CHUNK_SIZE,
) -> dict[str, Any]:
    """
    Send a list of state dicts in one or more /flights/batch calls.

    `states_payload` is the list of objects produced by
    `StateVector.to_api_payload()` (or any compatible dict).

    Returns an aggregate summary:
        {
          "sent": int,           # records accepted by the API
          "rejected": int,       # records rejected (partial accept)
          "failed_chunks": int,  # chunks that never reached the API
          "chunks": int,         # chunks attempted
          "duration_ms": int,
        }
    """
    if not states_payload:
        return {"sent": 0, "rejected": 0, "failed_chunks": 0, "chunks": 0, "duration_ms": 0}

    src = source or SOURCE_TAG
    sent = 0
    rejected = 0
    failed_chunks = 0
    duration_ms = 0
    chunks = 0

    for chunk in _iter_chunks(states_payload, chunk_size):
        chunks += 1
        body = {"states": chunk, "source": src}
        resp, meta = _post_with_retry(BATCH_PATH, body)
        duration_ms += meta.get("elapsed_ms", 0)

        if resp is None:
            failed_chunks += 1
            logger.error("batch chunk dropped (network failure): meta=%s", meta)
            rejected += len(chunk)
            continue

        result = _summarize_response(resp)
        if not result["ok"]:
            failed_chunks += 1
            rejected += len(chunk)
            logger.error(
                "batch chunk rejected by API: status=%s body=%s",
                resp.status_code,
                result["body"],
            )
            continue

        body_json = result["body"] or {}
        accepted = int(body_json.get("accepted", len(chunk)))
        chunk_rejected = int(body_json.get("rejected", 0))
        sent += accepted
        rejected += chunk_rejected
        logger.info(
            "batch chunk delivered: status=%d accepted=%d rejected=%d attempts=%d elapsed_ms=%d",
            resp.status_code, accepted, chunk_rejected,
            meta.get("attempts"), meta.get("elapsed_ms"),
        )

    return {
        "sent": sent,
        "rejected": rejected,
        "failed_chunks": failed_chunks,
        "chunks": chunks,
        "duration_ms": duration_ms,
    }


def send_states_to_api_single(
    states_payload: list[dict],
    *,
    source: str | None = None,
    max_in_flight: int = 10,
) -> dict[str, Any]:
    """
    Send each state as its own POST to /flights.

    The 'source' tag is sent as a top-level field in the body; the API
    forwards it to the DLQ entry on rejection.

    Uses a small thread pool to overlap network calls without hammering
    the API. This method is convenient for low-volume feeds or for
    isolating per-record failures.

    Returns an aggregate summary:
        {
          "sent": int,
          "rejected": int,
          "failed": int,        # network errors (request never reached the API)
          "requests": int,
          "duration_ms": int,
        }
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed

    if not states_payload:
        return {"sent": 0, "rejected": 0, "failed": 0, "requests": 0, "duration_ms": 0}

    _validate_config()
    src = source or SOURCE_TAG
    start = time.perf_counter()
    sent = 0
    rejected = 0
    failed = 0
    requests_total = 0

    def _send_one(state: dict) -> dict[str, Any]:
        body = dict(state)
        body["source"] = src
        resp, meta = _post_with_retry(SINGLE_PATH, body)
        if resp is None:
            return {"kind": "network_error", "meta": meta, "state": state}
        result = _summarize_response(resp)
        return {"kind": "http", "result": result, "meta": meta, "state": state}

    with ThreadPoolExecutor(max_workers=max_in_flight) as pool:
        futures = [pool.submit(_send_one, s) for s in states_payload]
        for fut in as_completed(futures):
            requests_total += 1
            outcome = fut.result()
            if outcome["kind"] == "network_error":
                failed += 1
                logger.error("single request dropped: meta=%s", outcome["meta"])
                continue
            result = outcome["result"]
            if not result["ok"]:
                # 4xx means the API accepted the request and explicitly
                # rejected the payload (validation / partial accept -> 400).
                # 5xx is also a non-success; treat both as rejected for
                # accounting purposes.
                rejected += 1
                logger.warning(
                    "single request rejected: status=%d body=%s",
                    result["status_code"], result["body"],
                )
            else:
                sent += 1
                body = result["body"] or {}
                logger.debug(
                    "single request accepted: status=%d accepted=%s",
                    result["status_code"], body.get("accepted"),
                )

    return {
        "sent": sent,
        "rejected": rejected,
        "failed": failed,
        "requests": requests_total,
        "duration_ms": int((time.perf_counter() - start) * 1000),
    }
