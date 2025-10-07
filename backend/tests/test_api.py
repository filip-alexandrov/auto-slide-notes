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
