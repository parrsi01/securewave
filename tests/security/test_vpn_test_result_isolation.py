import json
from datetime import datetime

from models.user import User
from services.jwt_service import create_access_token


def _result(run_id: str, *, detected: bool = True) -> dict:
    return {
        "run_id": run_id,
        "timestamp": datetime.utcnow().isoformat(),
        "vpn_detected": detected,
        "vpn_interface": "test-interface" if detected else None,
        "latency": {"avg_latency_ms": 5},
        "throughput": {"avg_download_mbps": 10},
        "dns_leak": {"leak_detected": False},
        "ipv6_leak": {"leak_detected": False},
        "ad_blocking": {"ads_blocked_percent": 0, "trackers_blocked_percent": 0},
        "stability": {"tunnel_drops": 0, "uptime_percent": 100},
        "scoring": {"overall_score": 80, "status": "PASSED", "individual_scores": {}},
        "test_duration_seconds": 1,
        "private_measurement": "must-not-cross-account-boundaries",
    }


def _write_latest(directory, result: dict) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "latest.json").write_text(json.dumps(result), encoding="utf-8")


def test_anonymous_vpn_test_views_preserve_shape_without_result_data(
    client, monkeypatch, tmp_path
):
    from routes import vpn_tests

    monkeypatch.setattr(vpn_tests, "RESULTS_DIR", tmp_path)
    _write_latest(tmp_path, _result("legacy-global-result"))

    status_response = client.get("/api/vpn/tests/status")
    assert status_response.status_code == 200
    assert status_response.json() == {
        "running": False,
        "has_results": False,
        "last_run": None,
    }

    latest_response = client.get("/api/vpn/tests/latest")
    assert latest_response.status_code == 200
    assert latest_response.json()["status"] == "UNAVAILABLE"
    assert latest_response.json()["run_id"] is None

    full_response = client.get("/api/vpn/tests/latest/full")
    assert full_response.status_code == 200
    assert full_response.json()["vpn_detected"] is False
    assert "private_measurement" not in full_response.json()


def test_vpn_test_results_are_isolated_between_accounts(
    client, db, test_user, auth_headers, monkeypatch, tmp_path
):
    from routes import vpn_tests

    monkeypatch.setattr(vpn_tests, "RESULTS_DIR", tmp_path)
    _write_latest(
        vpn_tests.get_user_results_dir(test_user.id),
        _result("owner-result"),
    )

    owner_response = client.get("/api/vpn/tests/latest/full", headers=auth_headers)
    assert owner_response.status_code == 200
    assert owner_response.json()["run_id"] == "owner-result"

    other_user = User(
        email="other-vpn-test-user@example.com",
        hashed_password="not-used-by-this-test",
        email_verified=True,
        is_active=True,
    )
    db.add(other_user)
    db.commit()
    db.refresh(other_user)
    other_headers = {
        "Authorization": f"Bearer {create_access_token(other_user)}",
    }

    other_response = client.get("/api/vpn/tests/latest/full", headers=other_headers)
    assert other_response.status_code == 200
    assert other_response.json()["vpn_detected"] is False
    assert other_response.json()["run_id"] != "owner-result"


def test_vpn_test_history_uses_only_the_callers_directory(
    client, test_user, auth_headers, monkeypatch, tmp_path
):
    from routes import vpn_tests

    monkeypatch.setattr(vpn_tests, "RESULTS_DIR", tmp_path)
    owner_dir = vpn_tests.get_user_results_dir(test_user.id)
    _write_latest(owner_dir, _result("owner-latest"))
    (owner_dir / "results_owner.json").write_text(
        json.dumps(_result("owner-history")), encoding="utf-8"
    )
    _write_latest(tmp_path / "user-999999", _result("other-history"))
    (tmp_path / "user-999999" / "results_other.json").write_text(
        json.dumps(_result("other-history")), encoding="utf-8"
    )

    response = client.get("/api/vpn/tests/history", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["count"] == 1
    assert response.json()["results"][0]["file"] == "results_owner.json"
