"""Shared boto3 client construction for the AWS-backed integrations.

The S3 storage, SES email, and KMS encryption backends all build a boto3
client the same way: guard the optional import, raise a install-hint
``ImportError`` when boto3 is absent, and assemble the credential kwargs with
an optional ``endpoint_url`` override used by LocalStack-style stacks.

This module owns that single seam. It deliberately knows nothing about the
backends themselves, so the storage/email/encryption factories and protocols
stay untouched.
"""

from __future__ import annotations

from typing import Any

try:
    import boto3
except ImportError:  # pragma: no cover
    boto3 = None  # type: ignore[assignment]

__all__ = ["build_client"]

# All AWS integrations ship in the same optional dependency group.
_EXTRA = "s3"


def build_client(
    service: str,
    *,
    region: str,
    access_key_id: str,
    secret_access_key: str,
    endpoint_url: str = "",
    feature: str,
    note: str = "",
) -> Any:
    """Return a boto3 client for ``service``.

    ``feature`` names the caller in the missing-dependency error (for example
    ``"S3 storage"``), and ``note`` appends an optional trailing sentence to
    that same message. ``endpoint_url`` is only forwarded when non-empty so
    boto3 keeps resolving the regional endpoint by default.
    """
    if boto3 is None:
        message = f"boto3 is required for {feature}. Install it with: pip install rentivo[{_EXTRA}]"
        if note:
            message = f"{message} {note}"
        raise ImportError(message)

    client_kwargs: dict = {
        "service_name": service,
        "region_name": region,
        "aws_access_key_id": access_key_id,
        "aws_secret_access_key": secret_access_key,
    }
    if endpoint_url:
        client_kwargs["endpoint_url"] = endpoint_url
    return boto3.client(**client_kwargs)
