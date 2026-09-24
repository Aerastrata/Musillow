# Musillow Backend

Multi-user recommendation & profile API for Musillow (see
`../music-discovery-spec.docx`). FastAPI + PostgreSQL, JWT accounts, per-user
encrypted connectors. Exposed over your **NetBird** overlay — no public reverse
proxy or TLS termination needed; point the app at the NetBird peer address.

## Architecture

- **FastAPI** app (`app/`), structured into routers.
- **PostgreSQL** via SQLAlchemy 2.0 async; schema managed by **Alembic**
  (migrations run automatically on container start).
- **JWT** bearer auth; passwords hashed with bcrypt.
- **Per-user connectors** (Navidrome / Audiobookshelf) — the secret is
  **encrypted at rest** (Fernet, keyed off `SECRET_KEY`). The recommender reads
  each user's own Navidrome library.

## Endpoints

Auth:
- `POST /auth/register` `{username, password, email?}` → `{access_token}`
- `POST /auth/login` `{username, password}` → `{access_token}`
- `GET  /auth/me` → current user

Connectors (Bearer required):
- `GET    /me/connectors` → list
- `PUT    /me/connectors` `{kind, baseUrl, username, secret}` (validates Navidrome)
- `DELETE /me/connectors/{kind}`

Recommendations & signals (Bearer required):
- `GET  /quick-picks` → 3×3 grid (Replay / Forgotten / Wildcard)
- `GET  /playlists/{type}` → `replay | forgotten | wildcard | daily`
- `POST /signals` `{type, trackId}` — like / playlist_add / play_complete / play / skip / expire
- `GET  /signals/recent`

`GET /health` is unauthenticated. Interactive docs at `/docs`.

## Run

```bash
cp .env.example .env      # set POSTGRES_PASSWORD, JWT_SECRET, SECRET_KEY
docker compose up --build -d
curl localhost:8080/health
```

Migrations apply automatically on start. Then, from the app (or curl), register
a user, add a Navidrome connector, and hit `/quick-picks`.

## Roadmap

- **Now:** accounts, connectors, per-user Navidrome-backed recs + signals.
- **Phase 2:** `/music/discover/` rotation + SoulSync + keep/delete.
- **Phase 3:** Troi patches (ListenBrainz/MusicBrainz).
- **Phase 4:** LB-Radio on-demand, charts, unified cross-service profile.
