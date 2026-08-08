"""Analytics events carried back to the edge as response headers.

Handlers never talk to an analytics backend directly: they tag the response and
the edge forwards the tagged events. Metadata names are snake_case at the call
site and title-cased in the header name.
"""

from __future__ import annotations

from fastapi import Response

ANALYTICS_HEADER_PREFIX = "X-Rentivo-Analytics"
ANALYTICS_EVENT_HEADER = f"{ANALYTICS_HEADER_PREFIX}-Event"


def set_analytics(response: Response, event: str, **metadata: str | int) -> None:
    response.headers[ANALYTICS_EVENT_HEADER] = event
    for name, value in metadata.items():
        header = "-".join(part.title() for part in name.split("_"))
        response.headers[f"{ANALYTICS_HEADER_PREFIX}-{header}"] = str(value)
