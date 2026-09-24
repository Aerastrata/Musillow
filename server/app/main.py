"""Musillow backend — multi-user recommendation & profile API.

Auth: JWT bearer tokens (see /auth). Each user stores their own Navidrome/ABS
connectors; recommendations and signals are per-user. Exposed over NetBird.
"""
import asyncio
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import fulfill, http
from .routers import abs as abs_router
from .routers import (
    auth,
    catalog,
    connectors,
    home,
    library,
    recommend,
    signals,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    # follow_redirects: the Apple Music RSS charts endpoint 301-redirects.
    client = httpx.AsyncClient(follow_redirects=True)
    http.set_client(client)
    # Re-drive any download requests left pending across a restart.
    asyncio.create_task(fulfill.process_pending())
    try:
        yield
    finally:
        await client.aclose()


app = FastAPI(title="Musillow Backend", version="0.2.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok"}


app.include_router(abs_router.router)
app.include_router(auth.router)
app.include_router(catalog.router)
app.include_router(connectors.router)
app.include_router(home.router)
app.include_router(library.router)
app.include_router(recommend.router)
app.include_router(signals.router)
