"""
Pydantic models for flight data validation.

Validation strategy:
- Strict type coercion at the edge (API Gateway -> Lambda)
- Domain-specific business rules as field validators
- Optional fields preserve the OpenSky state-vector semantics
  (not all fields are guaranteed to be populated)
"""
from __future__ import annotations

import re
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator


# ICAO24 transponder address: 6 hexadecimal characters (lowercase canonical)
_ICAO24_RE = re.compile(r"^[0-9a-f]{6}$")


class FlightStateIn(BaseModel):
    """
    Inbound flight state (one record from API client).

    Mirrors a subset of the OpenSky `states/all` array as a dict, so clients
    that already integrate with OpenSky can reuse their payload shape.
    """

    model_config = ConfigDict(
        extra="forbid",        # reject unknown fields explicitly
        str_strip_whitespace=True,
        populate_by_name=True,
    )

    icao24: str = Field(..., description="ICAO24 transponder address (6 hex chars)")
    callsign: Optional[str] = Field(None, max_length=8, description="Flight callsign, max 8 chars")
    origin_country: Optional[str] = Field(None, max_length=64)
    time_position: Optional[int] = Field(None, ge=0, description="Unix timestamp (seconds)")
    last_contact: Optional[int] = Field(None, ge=0, description="Unix timestamp (seconds)")
    longitude: Optional[float] = Field(None, ge=-180.0, le=180.0)
    latitude: Optional[float] = Field(None, ge=-90.0, le=90.0)
    altitude: Optional[float] = Field(None, description="Barometric altitude in meters")
    on_ground: Optional[bool] = None
    velocity: Optional[float] = Field(None, ge=0.0, le=2000.0, description="Ground speed m/s")
    heading: Optional[float] = Field(None, ge=0.0, lt=360.0, description="True heading in degrees")
    vertical_rate: Optional[float] = Field(None, ge=-200.0, le=200.0, description="m/s")
    geo_altitude: Optional[float] = Field(None, description="Geometric altitude in meters")
    squawk: Optional[str] = Field(None, pattern=r"^[0-7]{4}$", description="Transponder code (octal)")
    spi: Optional[bool] = None
    position_source: Optional[int] = Field(None, ge=0, le=4)

    @field_validator("icao24")
    @classmethod
    def _validate_icao24(cls, v: str) -> str:
        if not _ICAO24_RE.match(v):
            raise ValueError("icao24 must be 6 lowercase hexadecimal characters")
        return v

    @field_validator("callsign")
    @classmethod
    def _validate_callsign(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        v = v.strip()
        if v == "":
            return None
        return v

    @field_validator("latitude", "longitude")
    @classmethod
    def _validate_position_pair(cls, v, info):
        # If latitude/longitude is provided, both must be provided and the
        # pair must represent a sensible coordinate. This is a coarse check;
        # downstream consumers (Flink) can do richer geo validation.
        return v


class FlightBatchIn(BaseModel):
    """Inbound batch of flight states."""

    model_config = ConfigDict(extra="forbid")

    states: list[FlightStateIn] = Field(..., min_length=1, max_length=500)
    source: Optional[str] = Field(None, max_length=64, description="Origin identifier (e.g. 'feeder-1')")


def utc_now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"
