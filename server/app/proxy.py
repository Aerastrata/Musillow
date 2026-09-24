"""Shared upstream byte proxy (audio + images).

Both connectors stream media through the backend so the phone never needs to
reach Navidrome or Audiobookshelf directly. Range/partial-content semantics are
preserved verbatim, which is what makes seeking work.
"""
from fastapi import HTTPException
from fastapi.responses import StreamingResponse
from starlette.background import BackgroundTask

from . import http

# Response headers worth forwarding from the upstream server to the client.
_PASS_HEADERS = {
    "content-type",
    "content-length",
    "content-range",
    "accept-ranges",
    "cache-control",
    "content-disposition",
    "etag",
    "last-modified",
}


async def stream_proxy(
    url: str,
    *,
    params: dict | None = None,
    headers: dict | None = None,
    range_header: str | None = None,
) -> StreamingResponse:
    """Open a streaming GET upstream and relay it to the client verbatim."""
    client = http.client()
    fwd = dict(headers or {})
    if range_header:
        fwd["Range"] = range_header
    req = client.build_request(
        "GET", url, params=params, headers=fwd, timeout=None
    )
    try:
        resp = await client.send(req, stream=True)
    except Exception:
        raise HTTPException(status_code=502, detail="Upstream media error")
    if resp.status_code >= 400:
        await resp.aclose()
        raise HTTPException(status_code=502, detail="Upstream media error")
    return StreamingResponse(
        resp.aiter_raw(),
        status_code=resp.status_code,
        headers={
            k: v for k, v in resp.headers.items() if k.lower() in _PASS_HEADERS
        },
        background=BackgroundTask(resp.aclose),
    )
