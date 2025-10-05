import pytest

from app.storage import InvalidImage, SlideStore, png_size

from .conftest import make_png


def test_png_size_reads_header():
    assert png_size(make_png(160, 90)) == (160, 90)


def test_png_size_rejects_other_data():
    with pytest.raises(InvalidImage):
        png_size(b"GIF89a" + b"\x00" * 30)


def test_ids_grow_and_survive_restart(tmp_path, png):
    store = SlideStore(tmp_path)
    first = store.add(png)
    second = store.add(png)
    assert (first.id, second.id) == (1, 2)

    reopened = SlideStore(tmp_path)
    assert reopened.latest_id == 2
    assert [s.id for s in reopened.after(1)] == [2]


def test_clear_keeps_counting(tmp_path, png):
    store = SlideStore(tmp_path)
    store.add(png)
    assert store.clear() == 1
    assert list(store.images.iterdir()) == []
    assert store.add(png).id == 2
