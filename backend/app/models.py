"""API models."""

from datetime import datetime

from pydantic import BaseModel


class Slide(BaseModel):
    """A screenshot uploaded by the Mac app."""

    id: int
    filename: str
    width: int
    height: int
    created_at: datetime


class SlideList(BaseModel):
    """Slides newer than the id the iPad asked for."""

    slides: list[Slide]
    latest_id: int


class Health(BaseModel):
    status: str
    slides: int
