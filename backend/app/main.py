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

    @app.post("/slides", response_model=Slide, status_code=201)
    async def upload_slide(file: UploadFile, store: SlideStore = Depends(get_store)) -> Slide:
        data = await file.read(settings.max_upload_bytes + 1)
        if len(data) > settings.max_upload_bytes:
            raise HTTPException(413, "Slide is too large")
        try:
            slide = store.add(data)
        except InvalidImage as e:
            raise HTTPException(415, str(e)) from e
        log.info("slide %d (%dx%d)", slide.id, slide.width, slide.height)
        return slide

    @app.get("/slides", response_model=SlideList)
    def list_slides(
        after: int = Query(0, ge=0), store: SlideStore = Depends(get_store)
    ) -> SlideList:
        return SlideList(slides=store.after(after), latest_id=store.latest_id)

    @app.get("/slides/{slide_id}/image")
    def slide_image(slide_id: int, store: SlideStore = Depends(get_store)) -> FileResponse:
        slide = store.get(slide_id)
        if slide is None or not store.image_path(slide).exists():
            raise HTTPException(404, "No such slide")
        return FileResponse(store.image_path(slide), media_type="image/png")

    return app


app = create_app()
