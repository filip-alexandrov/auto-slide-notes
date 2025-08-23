"""Server settings, read from environment variables."""

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    max_upload_bytes: int
    host: str
    port: int


def load_settings() -> Settings:
    base = Path(__file__).resolve().parent.parent
    return Settings(
        data_dir=Path(os.environ.get("SLIDES_DATA_DIR", base / "data")),
        max_upload_bytes=int(os.environ.get("SLIDES_MAX_UPLOAD", 20 * 1024 * 1024)),
        host=os.environ.get("SLIDES_HOST", "0.0.0.0"),
        port=int(os.environ.get("SLIDES_PORT", 8000)),
    )
