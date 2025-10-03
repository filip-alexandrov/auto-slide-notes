import pytest

from app.storage import InvalidImage, SlideStore, png_size

from .conftest import make_png


def test_png_size_reads_header():
    assert png_size(make_png(160, 90)) == (160, 90)


def test_png_size_rejects_other_data():
    with pytest.raises(InvalidImage):
        png_size(b"GIF89a" + b"\x00" * 30)
