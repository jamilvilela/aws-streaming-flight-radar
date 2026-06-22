"""Base verifier class with shared AWS client factory."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Optional

import boto3
from botocore.config import Config as BotoConfig

from ..core.config import DeployConfig
from ..ui import console


class ResourceVerifier(ABC):
    """Abstract base for all post-deployment resource verifiers."""

    def __init__(self, config: DeployConfig):
        self._config = config
        self._boto_config = BotoConfig(
            region_name=config.aws_region,
            retries={"max_attempts": 3, "mode": "standard"},
        )

    @abstractmethod
    def verify(self) -> bool:
        """Run verification. Returns True if all resources are OK."""
        ...

    @property
    def name(self) -> str:
        """Human-readable verifier name."""
        return self.__class__.__name__

    # ── Boto3 client factory ─────────────────────────────────────────

    def _client(self, service: str) -> Any:
        """Get a boto3 client for the given service."""
        return boto3.client(service, region_name=self._config.aws_region, config=self._boto_config)

    # ── Helpers ──────────────────────────────────────────────────────

    def _get_project_prefix(self) -> str:
        """Get the project resource name prefix."""
        return self._config.project_name

    def _safe_query(
        self,
        service: str,
        method: str,
        error_msg: str = "",
        **kwargs,
    ) -> Optional[Any]:
        """Safely call an AWS API method, returning None on error."""
        try:
            client = self._client(service)
            method_fn = getattr(client, method)
            return method_fn(**kwargs)
        except Exception as e:
            if error_msg:
                console.warn(f"{error_msg}: {e}")
            return None
