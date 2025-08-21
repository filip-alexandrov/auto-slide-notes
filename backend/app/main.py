"""Relay between the Mac capture app and the iPad notes app.

The Mac uploads each screenshot with `POST /slides`. The iPad polls
`GET /slides?after=<id>` every 500 ms and downloads new images.
"""

import logging

from fastapi import Depends, FastAPI, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse

log = logging.getLogger("slides")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()
    store = SlideStore(settings.data_dir)
    app = FastAPI(title="Slide relay", version="0.1.0")
    app.state.store = store
    app.state.settings = settings

    return app


app = create_app()
