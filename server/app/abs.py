"""Minimal async Audiobookshelf client, instantiated per user.

Musillow stores the ABS *password* (encrypted) rather than a login token, and
mints tokens here on demand. A token being revoked or expiring server-side then
heals itself on the next call instead of stranding the account.

Everything returned here is already normalised into the shape the app consumes;
media (covers, author images, audio files) is never linked directly — callers
get ids and fetch the bytes back through the backend's own /abs/* proxy routes.
"""
import asyncio

import httpx


class AbsError(RuntimeError):
    pass


# Cached login tokens, keyed by (base_url, username). ABS tokens are long-lived,
# so re-logging in on every request would be wasteful.
_tokens: dict[tuple[str, str], str] = {}
_token_lock = asyncio.Lock()


def normalize(url: str) -> str:
    return url.strip().rstrip("/")


def forget(base_url: str, username: str) -> None:
    """Drop a cached login token — called when the connector changes or goes
    away, so a re-saved credential is never shadowed by the old session."""
    _tokens.pop((normalize(base_url), username), None)


async def login(
    base_url: str, username: str, password: str, client: httpx.AsyncClient
) -> tuple[str, str | None]:
    """Authenticate and return (token, default_library_id)."""
    base = normalize(base_url)
    try:
        resp = await client.post(
            f"{base}/login",
            json={"username": username, "password": password},
            timeout=20,
        )
    except Exception:
        raise AbsError("Could not reach the Audiobookshelf server")
    if resp.status_code != 200:
        raise AbsError(f"Login rejected (HTTP {resp.status_code})")
    body = resp.json()
    token = (body.get("user") or {}).get("token")
    if not token:
        raise AbsError("No token returned by Audiobookshelf")
    default_lib = body.get("userDefaultLibraryId")
    return str(token), str(default_lib) if default_lib else None


class Abs:
    def __init__(
        self, base_url: str, username: str, password: str, client: httpx.AsyncClient
    ):
        self.base = normalize(base_url)
        self.username = username
        self._password = password
        self._client = client

    @property
    def _cache_key(self) -> tuple[str, str]:
        return (self.base, self.username)

    async def token(self, *, refresh: bool = False) -> str:
        async with _token_lock:
            if not refresh:
                cached = _tokens.get(self._cache_key)
                if cached:
                    return cached
            token, _ = await login(
                self.base, self.username, self._password, self._client
            )
            _tokens[self._cache_key] = token
            return token

    async def auth_headers(self, *, refresh: bool = False) -> dict:
        return {"Authorization": f"Bearer {await self.token(refresh=refresh)}"}

    async def _request(
        self, method: str, path: str, *, params: dict | None = None, json=None
    ) -> httpx.Response:
        """One request, retried once against a freshly-minted token on 401."""
        for refresh in (False, True):
            headers = await self.auth_headers(refresh=refresh)
            try:
                resp = await self._client.request(
                    method,
                    f"{self.base}{path}",
                    params=params,
                    json=json,
                    headers=headers,
                    timeout=30,
                )
            except Exception:
                raise AbsError("Could not reach the Audiobookshelf server")
            if resp.status_code != 401:
                return resp
        raise AbsError("Audiobookshelf rejected the stored credentials")

    async def _get(self, path: str, params: dict | None = None) -> dict:
        resp = await self._request("GET", path, params=params)
        if resp.status_code == 404:
            raise AbsError("Not found")
        if resp.status_code != 200:
            raise AbsError(f"HTTP {resp.status_code}")
        try:
            return resp.json()
        except Exception:
            raise AbsError("Malformed response")

    # ---- Metadata ---------------------------------------------------------

    async def ping(self) -> None:
        await self._get("/api/libraries")

    async def libraries(self) -> list[dict]:
        body = await self._get("/api/libraries")
        return [
            {
                "id": str(lib.get("id")),
                "name": str(lib.get("name") or ""),
                "mediaType": str(lib.get("mediaType") or "book"),
            }
            for lib in (body.get("libraries") or [])
        ]

    async def book_library_id(self) -> str | None:
        """The first "book" library (falls back to the first library)."""
        libs = await self.libraries()
        if not libs:
            return None
        return next(
            (lib["id"] for lib in libs if lib["mediaType"] == "book"), libs[0]["id"]
        )

    @staticmethod
    def _book(item: dict) -> dict:
        md = ((item.get("media") or {}).get("metadata")) or {}
        item_id = str(item.get("id"))
        return {
            "id": item_id,
            "title": str(md.get("title") or "Untitled"),
            "author": str(md.get("authorName") or ""),
            "seriesName": md.get("seriesName"),
            # The app builds /abs/cover/<id> from this; no direct ABS link.
            "coverArt": item_id,
        }

    async def books(self, library_id: str) -> list[dict]:
        body = await self._get(f"/api/libraries/{library_id}/items", {"limit": 0})
        return [self._book(x) for x in (body.get("results") or [])]

    async def authors(self, library_id: str) -> list[dict]:
        body = await self._get(f"/api/libraries/{library_id}/authors")
        out = []
        for a in body.get("authors") or []:
            author_id = str(a.get("id"))
            out.append(
                {
                    "id": author_id,
                    "name": str(a.get("name") or ""),
                    "numBooks": a.get("numBooks")
                    if isinstance(a.get("numBooks"), int)
                    else None,
                }
            )
        return out

    async def series(self, library_id: str) -> list[dict]:
        body = await self._get(f"/api/libraries/{library_id}/series")
        return [
            {
                "id": str(s.get("id")),
                "name": str(s.get("name") or ""),
                "books": [self._book(b) for b in (s.get("books") or [])],
            }
            for s in (body.get("results") or [])
        ]

    async def author_books(self, author_id: str) -> list[dict]:
        body = await self._get(f"/api/authors/{author_id}", {"include": "items"})
        return [self._book(x) for x in (body.get("libraryItems") or [])]

    async def book_tracks(self, item_id: str) -> dict:
        """A book's playable audio files, plus the metadata the player needs.

        Returns ``{"id", "title", "author", "coverArt", "tracks": [...]}`` where
        each track carries the ``ino`` the /abs/audio proxy streams by.
        """
        body = await self._get(f"/api/items/{item_id}", {"expanded": 1})
        media = body.get("media") or {}
        md = media.get("metadata") or {}
        title = str(md.get("title") or "Audiobook")
        author = str(md.get("authorName") or "")
        files = media.get("audioFiles") or []
        tracks = []
        for i, f in enumerate(files):
            ino = f.get("ino")
            if ino is None:
                continue
            fmd = f.get("metadata") or {}
            name = str(fmd.get("filename") or f"Part {i + 1}")
            duration = f.get("duration")
            tracks.append(
                {
                    "id": f"{item_id}:{ino}",
                    "itemId": item_id,
                    "ino": str(ino),
                    "title": title if len(files) == 1 else name,
                    "artist": author or title,
                    "coverArt": item_id,
                    "duration": round(duration) if isinstance(duration, (int, float)) else None,
                }
            )
        return {
            "id": item_id,
            "title": title,
            "author": author,
            "coverArt": item_id,
            "tracks": tracks,
        }

    async def in_progress(self, limit: int = 10) -> list[dict]:
        """Books the user is part-way through, most recent first.

        Feeds the home screen's "Continue listening" row. Progress is read from
        the payload when the server includes it, so this stays one request
        rather than one per book.
        """
        try:
            body = await self._get("/api/me/items-in-progress")
        except AbsError:
            return []
        out = []
        for item in (body.get("libraryItems") or [])[:limit]:
            book = self._book(item)
            progress = (
                item.get("userMediaProgress")
                or item.get("mediaProgress")
                or item.get("progress")
                or {}
            )
            if not isinstance(progress, dict):
                progress = {}
            duration = float(progress.get("duration") or 0)
            current = float(progress.get("currentTime") or 0)
            fraction = progress.get("progress")
            if not isinstance(fraction, (int, float)):
                fraction = (current / duration) if duration > 0 else 0.0
            book["currentTime"] = current
            book["duration"] = duration
            book["progress"] = min(max(float(fraction), 0.0), 1.0)
            out.append(book)
        return out

    # ---- Progress ---------------------------------------------------------

    async def progress(self, item_id: str) -> dict:
        """Saved position for a book. Zeroes rather than failing when unset."""
        try:
            body = await self._get(f"/api/me/progress/{item_id}")
        except AbsError:
            return {"currentTime": 0.0, "duration": 0.0, "isFinished": False}
        return {
            "currentTime": float(body.get("currentTime") or 0),
            "duration": float(body.get("duration") or 0),
            "isFinished": bool(body.get("isFinished")),
        }

    async def update_progress(
        self,
        item_id: str,
        *,
        current_time: float,
        duration: float,
        is_finished: bool = False,
    ) -> None:
        progress = min(max(current_time / duration, 0.0), 1.0) if duration > 0 else 0.0
        await self._request(
            "PATCH",
            f"/api/me/progress/{item_id}",
            json={
                "currentTime": current_time,
                "duration": duration,
                "progress": progress,
                "isFinished": is_finished,
            },
        )

    async def stats(self) -> dict | None:
        """Listening stats (best-effort; None when the server has no endpoint)."""
        try:
            body = await self._get("/api/me/listening-stats")
        except AbsError:
            return None
        total_seconds = float(body.get("totalTime") or 0)
        finished = body.get("itemsFinished")
        if not isinstance(finished, int):
            finished = len(body.get("finishedItems") or [])
        days = len(body.get("days") or {})
        return {
            "totalHours": total_seconds / 3600.0,
            "itemsFinished": finished,
            "daysListened": days,
        }

    # ---- Raw media (for the byte proxy) -----------------------------------

    def cover_url(self, item_id: str) -> str:
        return f"{self.base}/api/items/{item_id}/cover"

    def author_image_url(self, author_id: str) -> str:
        return f"{self.base}/api/authors/{author_id}/image"

    def audio_url(self, item_id: str, ino: str) -> str:
        return f"{self.base}/api/items/{item_id}/file/{ino}"
