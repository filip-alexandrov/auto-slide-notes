import struct
import zlib

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def make_png(width: int = 4, height: int = 3) -> bytes:
    """A tiny valid PNG, so tests don't need image files."""

    def chunk(kind: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    rows = b"".join(b"\x00" + b"\xff\x00\x00" * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


@pytest.fixture
def png() -> bytes:
    return make_png()


@pytest.fixture
def settings(tmp_path) -> Settings:
    return Settings(data_dir=tmp_path, max_upload_bytes=1024, host="127.0.0.1", port=0)


@pytest.fixture
def client(settings) -> TestClient:
    return TestClient(create_app(settings))
