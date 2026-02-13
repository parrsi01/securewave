"""
Typed API error models and helpers for consistent responses/OpenAPI docs.
"""

from __future__ import annotations

from typing import Any, Dict

from fastapi import HTTPException
from pydantic import BaseModel, Field


class ApiErrorDetail(BaseModel):
    """Machine-readable API error payload."""

    code: str = Field(..., description="Stable error code for client handling.")
    message: str = Field(..., description="Human-readable error summary.")
    details: Any | None = Field(default=None, description="Optional structured metadata.")


class ApiErrorResponse(BaseModel):
    """Top-level API error envelope."""

    error: ApiErrorDetail
    request_id: str = Field(..., description="Request correlation identifier.")


class ApiException(HTTPException):
    """HTTPException with a stable API error code and optional details."""

    def __init__(
        self,
        *,
        status_code: int,
        code: str,
        message: str,
        details: Any | None = None,
    ) -> None:
        super().__init__(status_code=status_code, detail=message)
        self.code = code
        self.message = message
        self.details = details


def api_error_responses(status_to_description: Dict[int, str]) -> Dict[int, Dict[str, Any]]:
    """Build FastAPI response docs for typed error envelopes."""
    return {
        status_code: {
            "model": ApiErrorResponse,
            "description": description,
        }
        for status_code, description in status_to_description.items()
    }
