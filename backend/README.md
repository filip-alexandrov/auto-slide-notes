# Slide relay server

Small FastAPI server that relays screenshots from the Mac capture app to the
iPad notes app.

| Method | Path | |
|--------|------|---|
| `POST` | `/slides` | Upload a PNG (`multipart/form-data`, field `file`) |
| `GET` | `/slides?after=<id>` | Slides newer than `id` — the iPad polls this every 500 ms |
| `GET` | `/slides/<id>/image` | The PNG of one slide |
| `DELETE` | `/slides` | Remove all slides (ids keep counting) |
| `GET` | `/health` | Status and slide count |

## Run

```bash
./run.sh                 # creates .venv on first run, listens on 0.0.0.0:8000
```

Settings: `SLIDES_DATA_DIR`, `SLIDES_MAX_UPLOAD`, `SLIDES_HOST`, `SLIDES_PORT`.

## Test

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/pytest
```
