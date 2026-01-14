from app.core import config


def test_refresh_rotation(client):
    register = client.post("/api/auth/register", json={"email": "a@b.com", "password": "password123"})
    assert register.status_code == 200

    login = client.post("/api/auth/login", json={"email": "a@b.com", "password": "password123"})
    assert login.status_code == 200
    tokens = login.json()
    refresh = tokens["refresh_token"]

    refreshed = client.post("/api/auth/refresh", json={"refresh_token": refresh})
    assert refreshed.status_code == 200
    new_refresh = refreshed.json()["refresh_token"]
    assert new_refresh != refresh

    old_refresh = client.post("/api/auth/refresh", json={"refresh_token": refresh})
    assert old_refresh.status_code == 401


def test_device_limit_free_tier(client):
    config.FREE_DEVICE_LIMIT = 1

    register = client.post("/api/auth/register", json={"email": "c@d.com", "password": "password123"})
    assert register.status_code == 200
    token = register.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    device_1 = client.post("/api/devices/register", json={"name": "phone"}, headers=headers)
    assert device_1.status_code == 200

    device_2 = client.post("/api/devices/register", json={"name": "laptop"}, headers=headers)
    assert device_2.status_code == 400
