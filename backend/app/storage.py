"""Slides on disk: PNG files plus a JSON index."""

import json
import os
import struct
import threading
from datetime import datetime, timezone
from pathlib import Path

from .models import Slide

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class InvalidImage(ValueError):
    pass


def png_size(data: bytes) -> tuple[int, int]:
    """Width and height from the IHDR chunk of a PNG."""
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        raise InvalidImage("not a PNG image")
    width, height = struct.unpack(">II", data[16:24])
    if width == 0 or height == 0:
        raise InvalidImage("empty image")
    return width, height


class SlideStore:
    """Keeps slides in `root/images` and their metadata in `root/index.json`.

    Ids only ever grow, so the iPad can ask for everything after the last id
    it has seen.
    """

    def __init__(self, root: Path):
        self.root = Path(root)
        self.images = self.root / "images"
        self.images.mkdir(parents=True, exist_ok=True)
        self._index_file = self.root / "index.json"
        self._lock = threading.Lock()
        self._slides: list[Slide] = []
        self._latest_id = 0
        self._load()

    def _load(self) -> None:
        if not self._index_file.exists():
            return
        raw = json.loads(self._index_file.read_text())
        self._slides = [Slide.model_validate(s) for s in raw["slides"]]
        self._latest_id = raw["latest_id"]

    def _save(self) -> None:
        data = {
            "latest_id": self._latest_id,
            "slides": [s.model_dump(mode="json") for s in self._slides],
        }
        tmp = self._index_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=2))
        os.replace(tmp, self._index_file)

    @property
    def latest_id(self) -> int:
        return self._latest_id

    def __len__(self) -> int:
        return len(self._slides)

    def add(self, data: bytes) -> Slide:
        width, height = png_size(data)
        with self._lock:
            self._latest_id += 1
            slide_id = self._latest_id
            filename = f"slide_{slide_id:05d}.png"
            (self.images / filename).write_bytes(data)
            slide = Slide(
                id=slide_id,
                filename=filename,
                width=width,
                height=height,
                created_at=datetime.now(timezone.utc),
            )
            self._slides.append(slide)
            self._save()
            return slide

    def after(self, slide_id: int) -> list[Slide]:
        return [s for s in self._slides if s.id > slide_id]

    def get(self, slide_id: int) -> Slide | None:
        return next((s for s in self._slides if s.id == slide_id), None)
