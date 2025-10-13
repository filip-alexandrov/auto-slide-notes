def upload(client, data):
    return client.post("/slides", files={"file": ("slide.png", data, "image/png")})


def test_health(client):
    assert client.get("/health").json() == {"status": "ok", "slides": 0}


def test_upload_then_poll(client, png):
    created = upload(client, png)
    assert created.status_code == 201
    assert created.json()["id"] == 1

    body = client.get("/slides", params={"after": 0}).json()
    assert body["latest_id"] == 1
    assert [s["id"] for s in body["slides"]] == [1]

    # Nothing new after the latest id.
    assert client.get("/slides", params={"after": 1}).json()["slides"] == []


def test_image_download(client, png):
    upload(client, png)
    res = client.get("/slides/1/image")
    assert res.status_code == 200
    assert res.headers["content-type"] == "image/png"
    assert res.content == png


def test_missing_image(client):
    assert client.get("/slides/7/image").status_code == 404


def test_rejects_non_png(client):
    assert upload(client, b"not an image").status_code == 415


def test_rejects_large_upload(client, png):
    assert upload(client, png + b"\x00" * 2048).status_code == 413


def test_clear(client, png):
    upload(client, png)
    upload(client, png)
    assert client.delete("/slides").json() == {"removed": 2}
    assert client.get("/health").json()["slides"] == 0
