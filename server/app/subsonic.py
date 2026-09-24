"""Minimal async Subsonic client, instantiated per user with their credentials.

Uses the salted-token auth scheme (t = md5(password + salt)).
"""
import hashlib
import secrets
from datetime import datetime

import httpx


def _parse_ts(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def normalize_song(s: dict) -> dict:
    return {
        "id": str(s.get("id")),
        "title": s.get("title", "Unknown"),
        "artist": s.get("artist", "Unknown artist"),
        "album": s.get("album"),
        "albumId": s.get("albumId"),
        "coverArt": s.get("coverArt"),
        "genre": s.get("genre"),
        "duration": s.get("duration"),
        "playCount": int(s.get("playCount", 0) or 0),
        "lastPlayed": _parse_ts(s.get("played")),
        "starred": _parse_ts(s.get("starred")),
        "isStarred": bool(s.get("starred")),
    }


class SubsonicError(RuntimeError):
    pass


class Subsonic:
    def __init__(
        self, base_url: str, username: str, password: str, client: httpx.AsyncClient
    ):
        self.base = base_url.rstrip("/")
        self.username = username
        self._password = password
        self._client = client

    def _auth_params(self) -> dict:
        salt = secrets.token_hex(6)
        token = hashlib.md5((self._password + salt).encode()).hexdigest()
        return {
            "u": self.username,
            "t": token,
            "s": salt,
            "v": "1.16.1",
            "c": "musillow-server",
            "f": "json",
        }

    async def _get(self, endpoint: str, params: dict | None = None) -> dict:
        url = f"{self.base}/rest/{endpoint}"
        merged = {**self._auth_params(), **(params or {})}
        resp = await self._client.get(url, params=merged, timeout=30)
        resp.raise_for_status()
        sub = resp.json().get("subsonic-response", {})
        if sub.get("status") != "ok":
            msg = (sub.get("error") or {}).get("message", "Subsonic error")
            raise SubsonicError(msg)
        return sub

    async def ping(self) -> None:
        await self._get("ping.view")

    async def random_songs(self, size: int = 200) -> list[dict]:
        sub = await self._get("getRandomSongs.view", {"size": size})
        return [normalize_song(s) for s in (sub.get("randomSongs") or {}).get("song", [])]

    async def starred_songs(self) -> list[dict]:
        sub = await self._get("getStarred2.view")
        return [normalize_song(s) for s in (sub.get("starred2") or {}).get("song", [])]

    async def album_list2(
        self, list_type: str = "frequent", size: int = 50, offset: int = 0
    ) -> list[dict]:
        sub = await self._get(
            "getAlbumList2.view",
            {"type": list_type, "size": size, "offset": offset},
        )
        return (sub.get("albumList2") or {}).get("album", [])

    async def album_songs(self, album_id: str) -> list[dict]:
        sub = await self._get("getAlbum.view", {"id": album_id})
        return [normalize_song(s) for s in (sub.get("album") or {}).get("song", [])]

    async def song(self, song_id: str) -> dict | None:
        """One song by id (getSong). Used to put a body on a track the app has
        a play signal for but which isn't in any pool already fetched."""
        sub = await self._get("getSong.view", {"id": song_id})
        raw = sub.get("song")
        return normalize_song(raw) if raw else None

    async def start_scan(self) -> None:
        """Kick off a Navidrome library rescan so newly-added files show up."""
        await self._get("startScan.view")

    async def search3_songs(self, query: str, song_count: int = 30) -> list[dict]:
        """Song hits for a free-text query (used to resolve a recommended
        artist/title back to what the user actually owns)."""
        sub = await self._get(
            "search3.view",
            {
                "query": query,
                "artistCount": 0,
                "albumCount": 0,
                "songCount": song_count,
            },
        )
        return [
            normalize_song(s)
            for s in (sub.get("searchResult3") or {}).get("song", [])
        ]

    # ---- Full library surface (proxied straight to the client) -------------

    async def playlists(self) -> list[dict]:
        sub = await self._get("getPlaylists.view")
        return (sub.get("playlists") or {}).get("playlist", [])

    async def playlist(self, playlist_id: str) -> dict:
        sub = await self._get("getPlaylist.view", {"id": playlist_id})
        p = sub.get("playlist") or {}
        return {
            "id": str(p.get("id")),
            "name": p.get("name", "Playlist"),
            "coverArt": p.get("coverArt"),
            "songs": [normalize_song(s) for s in p.get("entry", [])],
        }

    async def create_playlist(
        self, name: str, song_ids: list[str] | None = None
    ) -> dict:
        """Create a new playlist and return it (id, name)."""
        sub = await self._get(
            "createPlaylist.view", {"name": name, "songId": song_ids or []}
        )
        p = sub.get("playlist") or {}
        # Older Navidrome builds return an empty body from createPlaylist; fall
        # back to looking the new playlist up by name.
        if not p.get("id"):
            for existing in await self.playlists():
                if existing.get("name") == name:
                    return {"id": str(existing.get("id")), "name": name}
        return {"id": str(p.get("id")), "name": p.get("name", name)}

    async def replace_playlist(self, playlist_id: str, song_ids: list[str]) -> None:
        """Overwrite a playlist's entire song list (and order) in one call.

        Subsonic's createPlaylist replaces membership wholesale when given an
        existing playlistId, which is how we persist reorders and removals.
        """
        await self._get(
            "createPlaylist.view",
            {"playlistId": playlist_id, "songId": song_ids},
        )

    async def rename_playlist(self, playlist_id: str, name: str) -> None:
        await self._get(
            "updatePlaylist.view", {"playlistId": playlist_id, "name": name}
        )

    async def add_to_playlist(self, playlist_id: str, song_ids: list[str]) -> None:
        await self._get(
            "updatePlaylist.view",
            {"playlistId": playlist_id, "songIdToAdd": song_ids},
        )

    async def delete_playlist(self, playlist_id: str) -> None:
        await self._get("deletePlaylist.view", {"id": playlist_id})

    async def cover_bytes(self, cover_id: str, size: int = 512) -> tuple[bytes, str]:
        """Fetch raw cover-art bytes (used to snapshot a song's art as a
        playlist cover). Returns (data, content_type)."""
        url = f"{self.base}/rest/getCoverArt.view"
        merged = {**self._auth_params(), "id": cover_id, "size": size}
        resp = await self._client.get(url, params=merged, timeout=30)
        resp.raise_for_status()
        return resp.content, resp.headers.get("content-type", "image/jpeg")

    async def albums(
        self, list_type: str = "alphabeticalByName", size: int = 100
    ) -> list[dict]:
        return await self.album_list2(list_type, size)

    async def album(self, album_id: str) -> dict:
        sub = await self._get("getAlbum.view", {"id": album_id})
        a = sub.get("album") or {}
        return {
            "id": str(a.get("id")),
            "name": a.get("name", "Album"),
            "artist": a.get("artist", ""),
            "coverArt": a.get("coverArt"),
            "songs": [normalize_song(s) for s in a.get("song", [])],
        }

    async def artists(self) -> list[dict]:
        sub = await self._get("getArtists.view")
        out: list[dict] = []
        for group in (sub.get("artists") or {}).get("index", []):
            out.extend(group.get("artist", []))
        return out

    async def artist_albums(self, artist_id: str) -> list[dict]:
        sub = await self._get("getArtist.view", {"id": artist_id})
        return (sub.get("artist") or {}).get("album", [])

    async def genres(self) -> list[str]:
        sub = await self._get("getGenres.view")
        rows = (sub.get("genres") or {}).get("genre", [])
        names = [str(g.get("value") or g.get("name") or "") for g in rows]
        return [n for n in names if n]

    async def songs_by_genre(self, genre: str, count: int = 200) -> list[dict]:
        sub = await self._get(
            "getSongsByGenre.view", {"genre": genre, "count": count}
        )
        return [
            normalize_song(s)
            for s in (sub.get("songsByGenre") or {}).get("song", [])
        ]

    async def internet_radio_stations(self) -> list[dict]:
        sub = await self._get("getInternetRadioStations.view")
        rows = (sub.get("internetRadioStations") or {}).get(
            "internetRadioStation", []
        )
        return [
            {
                "id": str(r.get("id")),
                "name": r.get("name", "Station"),
                "streamUrl": r.get("streamUrl"),
            }
            for r in rows
            if r.get("streamUrl")
        ]

    async def starred(self) -> dict:
        sub = await self._get("getStarred2.view")
        s = sub.get("starred2") or {}
        return {
            "songs": [normalize_song(x) for x in s.get("song", [])],
            "albums": s.get("album", []),
        }

    async def star(self, song_id: str) -> None:
        await self._get("star.view", {"id": song_id})

    async def unstar(self, song_id: str) -> None:
        await self._get("unstar.view", {"id": song_id})

    async def lyrics_by_song_id(self, song_id: str) -> dict:
        """Structured lyrics for a song via the OpenSubsonic extension.

        Returns ``{"synced": bool, "lines": [{"start": ms|None, "text": str}]}``.
        Prefers a synced track (with per-line millisecond offsets) when Navidrome
        has one, otherwise falls back to the plain ``getLyrics`` endpoint. Empty
        ``lines`` means no lyrics were found.
        """
        try:
            sub = await self._get("getLyricsBySongId.view", {"id": song_id})
        except SubsonicError:
            sub = {}
        tracks = ((sub.get("lyricsList") or {}).get("structuredLyrics")) or []
        if tracks:
            # Prefer a synced track; else take the first available.
            chosen = next((t for t in tracks if t.get("synced")), tracks[0])
            synced = bool(chosen.get("synced"))
            lines = [
                {
                    "start": ln.get("start") if synced else None,
                    "text": (ln.get("value") or "").rstrip(),
                }
                for ln in (chosen.get("line") or [])
            ]
            return {"synced": synced, "lines": lines}

        # Fallback: plain unsynced lyrics keyed by artist/title.
        try:
            plain = await self._get("getLyrics.view")
        except SubsonicError:
            plain = {}
        value = ((plain.get("lyrics") or {}).get("value") or "").strip()
        if not value:
            return {"synced": False, "lines": []}
        lines = [{"start": None, "text": ln} for ln in value.split("\n")]
        return {"synced": False, "lines": lines}

    async def similar_songs(self, song_id: str, count: int = 30) -> list[dict]:
        """Songs Navidrome considers similar to [song_id] (getSimilarSongs2)."""
        sub = await self._get(
            "getSimilarSongs2.view", {"id": song_id, "count": count}
        )
        songs = (sub.get("similarSongs2") or {}).get("song", [])
        return [normalize_song(s) for s in songs]

    # ---- Raw media (audio + cover art) for the byte proxy ------------------

    def media_url(self, endpoint: str) -> str:
        return f"{self.base}/rest/{endpoint}"

    def media_params(self, extra: dict | None = None) -> dict:
        return {**self._auth_params(), **(extra or {})}
