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
