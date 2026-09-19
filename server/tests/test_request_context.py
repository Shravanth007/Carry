import logging

import pytest

from tests.helpers import bearer


def test_every_response_gets_a_request_id(client):
    res = client.get("/health")

    assert len(res.headers["X-Request-ID"]) == 32


def test_the_apps_request_id_is_kept(client):
    res = client.get("/health", headers={"X-Request-ID": "app-123"})

    assert res.headers["X-Request-ID"] == "app-123"


@pytest.mark.parametrize(
    "bad_id",
    ["has space", "a" * 65, "semi;colon"],
    ids=["space", "too long", "symbol"],
)
def test_an_unsafe_request_id_is_replaced(client, bad_id):
    res = client.get("/health", headers={"X-Request-ID": bad_id})

    assert res.headers["X-Request-ID"] != bad_id
    assert len(res.headers["X-Request-ID"]) == 32


def test_logs_one_line_per_request_without_the_token(client, caplog):
    caplog.set_level(logging.INFO, logger="carry.request")

    client.get("/me", headers={**bearer("forged-token"), "X-Request-ID": "req-1"})

    [line] = [r.getMessage() for r in caplog.records if r.name == "carry.request"]
    assert line.startswith("GET /me 401 ")
    assert line.endswith("id=req-1")
    assert "forged-token" not in line
