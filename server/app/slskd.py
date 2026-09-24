"""Thin async client for the slskd (Soulseek daemon) REST API.

slskd already runs alongside SoulSync and is logged into the Soulseek network;
we drive it directly to fulfil download requests (search → pick a file →
enqueue the download).
"""
import httpx

from .config import settings

_V0 = "/api/v0"


def _headers() -> dict:
    return {"X-API-Key": settings.slskd_api_key}


def _base() -> str:
    return settings.slskd_url.rstrip("/")


async def create_search(client: httpx.AsyncClient, text: str) -> str | None:
    r = await client.post(
        f"{_base()}{_V0}/searches",
        headers={**_headers(), "content-type": "application/json"},
        json={"searchText": text},
        timeout=20,
    )
    if r.status_code not in (200, 201):
        return None
    return r.json().get("id")


async def search_state(client: httpx.AsyncClient, sid: str) -> dict:
    r = await client.get(
        f"{_base()}{_V0}/searches/{sid}", headers=_headers(), timeout=15
    )
    r.raise_for_status()
    return r.json()


async def search_responses(client: httpx.AsyncClient, sid: str) -> list[dict]:
    r = await client.get(
        f"{_base()}{_V0}/searches/{sid}/responses",
        headers=_headers(),
        timeout=30,
    )
    r.raise_for_status()
    return r.json()


async def get_downloads(client: httpx.AsyncClient) -> list[dict]:
    """All download transfers, grouped by user → directories → files."""
    r = await client.get(
        f"{_base()}{_V0}/transfers/downloads", headers=_headers(), timeout=20
    )
    r.raise_for_status()
    return r.json()


async def enqueue_download(
    client: httpx.AsyncClient, username: str, filename: str, size: int
) -> bool:
    r = await client.post(
        f"{_base()}{_V0}/transfers/downloads/{username}",
        headers={**_headers(), "content-type": "application/json"},
        json=[{"filename": filename, "size": size}],
        timeout=20,
    )
    return r.status_code in (200, 201)
