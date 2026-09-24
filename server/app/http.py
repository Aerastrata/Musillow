"""Process-wide shared httpx client (set during app lifespan)."""
import httpx

_client: httpx.AsyncClient | None = None


def set_client(client: httpx.AsyncClient) -> None:
    global _client
    _client = client


def client() -> httpx.AsyncClient:
    assert _client is not None, "HTTP client not initialised"
    return _client
