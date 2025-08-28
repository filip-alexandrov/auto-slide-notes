"""Relay between the Mac capture app and the iPad notes app.

The Mac uploads each screenshot with `POST /slides`. The iPad polls
`GET /slides?after=<id>` every 500 ms and downloads new images.
"""

import logging

from fastapi import Depends, FastAPI, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse

from .config import Settings, load_settings
from .models import Health, Slide, SlideList
from .storage import InvalidImage, SlideStore

log = logging.getLogger("slides")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()
    store = SlideStore(settings.data_dir)
    app = FastAPI(title="Slide relay", version="0.1.0")
    app.state.store = store
    app.state.settings = settings

    def get_store() -> SlideStore:
        return store

    @app.get("/health", response_model=Health)
    def health(store: SlideStore = Depends(get_store)) -> Health:
        return Health(status="ok", slides=len(store))

    return app


app = create_app()
