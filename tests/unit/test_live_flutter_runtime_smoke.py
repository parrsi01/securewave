import json
from pathlib import Path

import pytest

from scripts import live_flutter_runtime_smoke as smoke
from scripts import check_live_certification_inputs as input_check
from scripts import linux_app_vpn_tunnel_proof as certification


STAGING_API = "https://staging.example.test/api"


def _auth_file(tmp_path: Path, *, mode: int = 0o600) -> Path:
    path = tmp_path / "stable-account.env"
    path.write_text(
        "SECUREWAVE_RUNTIME_PROBE_EMAIL=stable@example.test\n"
        "SECUREWAVE_RUNTIME_PROBE_PASSWORD=StableSecret!A1\n",
        encoding="utf-8",
    )
    path.chmod(mode)
    return path


def test_live_smoke_has_no_registration_or_random_account_path():
    source = Path("scripts/live_flutter_runtime_smoke.py").read_text(encoding="utf-8")

    assert "/auth/register" not in source
    assert "secrets." not in source
    assert "--email" not in source
    assert "--password" not in source
    assert smoke.PROTOCOL == "wireguard"


def test_flutter_runner_requires_protected_file_and_explicit_staging():
    source = Path("scripts/run_flutter_linux.sh").read_text(encoding="utf-8")

    assert 'api_base="${SECUREWAVE_API_BASE_URL:-}"' in source
    assert "Production cannot be selected" in source
    assert 'stat -c \'%a\' "$credential_file"' in source
    assert '== "600"' in source
    assert "check_live_certification_inputs.py" in source
    assert '--data-binary "@$login_payload_file"' in source
    assert '-d "$login_payload"' not in source
    assert 'echo "Test account:' not in source
    assert 'echo "Account: $test_email"' not in source
    assert "SECUREWAVE_DEBUG_AUTO_LOGIN=false" in source
    assert "SECUREWAVE_DEBUG_EMAIL" not in source
    assert "SECUREWAVE_DEBUG_PASSWORD" not in source
    assert '--dart-define="SECUREWAVE_API_BASE_URL=$api_base"' in source
    assert '--dart-define="SECUREWAVE_USE_MOCK_API=false"' in source


def test_local_postgres_runner_is_pinned_loopback_and_disposable():
    source = Path("scripts/run_local_postgres_concurrency.sh").read_text(
        encoding="utf-8"
    )

    assert "postgres:15@sha256:" in source
    assert "--publish 127.0.0.1::5432" in source
    assert "tests/integration/test_postgres_usage_concurrency.py" in source
    assert 'trap cleanup EXIT INT TERM' in source
    assert 'docker rm "$container"' in source
    assert "api.securewaveapp.com" not in source


def test_live_smoke_requires_auth_file(capsys):
    with pytest.raises(SystemExit) as raised:
        smoke.main(["--api-base", STAGING_API, "--auth-file", "/missing/auth.env"])

    assert raised.value.code == 2
    assert "protected stable-account auth file is required" in capsys.readouterr().err


def test_live_smoke_rejects_insecure_auth_file(tmp_path, capsys):
    path = _auth_file(tmp_path, mode=0o644)

    with pytest.raises(SystemExit) as raised:
        smoke.main(["--api-base", STAGING_API, "--auth-file", str(path)])

    assert raised.value.code == 2
    assert "permissions must be owner-only" in capsys.readouterr().err


def test_certification_rejects_symlinked_auth_file(tmp_path):
    real = _auth_file(tmp_path)
    link = tmp_path / "linked.env"
    link.symlink_to(real)

    assert "must not be a symbolic link" in (
        certification._credential_file_security_error(link) or ""
    )


def test_input_preflight_reports_only_readiness(tmp_path, capsys):
    path = _auth_file(tmp_path)

    assert input_check.main(
        ["--api-base", STAGING_API, "--auth-file", str(path)]
    ) == 0

    output = capsys.readouterr().out
    assert output.splitlines() == [
        "auth_file=ready",
        "stable_account=ready",
        "api_target=staging",
        "protocol=wireguard",
    ]
    assert "stable@example.test" not in output
    assert "StableSecret!A1" not in output


def test_live_smoke_rejects_implicit_production(tmp_path, capsys):
    path = _auth_file(tmp_path)

    with pytest.raises(SystemExit) as raised:
        smoke.main(
            [
                "--api-base",
                "https://api.securewaveapp.com/api",
                "--auth-file",
                str(path),
            ]
        )

    assert raised.value.code == 2
    assert "production API certification is blocked" in capsys.readouterr().err


def test_live_smoke_uses_stable_login_and_redacts_output(tmp_path, monkeypatch, capsys):
    path = _auth_file(tmp_path)
    calls = []

    def fake_request(method, url, *, token=None, payload=None, timeout=20):
        calls.append((method, url, token, payload))
        if url.endswith("/health"):
            return 200, {"status": "healthy"}
        if url.endswith("/auth/login"):
            assert payload == {
                "email": "stable@example.test",
                "password": "StableSecret!A1",
            }
            return 200, {"access_token": "private-bearer-token"}
        if url.endswith("/auth/me"):
            return 200, {"email": "stable@example.test"}
        if url.endswith("/user/plan"):
            return 200, {"plan": "free"}
        if "/vpn/servers" in url:
            return 200, {"servers": [{"server_id": "server-private-id"}]}
        if url.endswith("/vpn/profile"):
            assert payload["protocol"] == "wireguard"
            return 200, {"wireguard_config": "private-profile"}
        raise AssertionError(url)

    monkeypatch.setattr(smoke, "_json_request", fake_request)

    assert smoke.main(
        ["--api-base", STAGING_API, "--auth-file", str(path), "--profile-repeats", "2"]
    ) == 0

    output = capsys.readouterr().out
    summary = json.loads(output)
    assert summary["ok"] is True
    assert summary["profile_statuses"] == [200, 200]
    for secret in (
        "stable@example.test",
        "StableSecret!A1",
        "private-bearer-token",
        "private-profile",
        "server-private-id",
    ):
        assert secret not in output
    assert not any(url.endswith("/auth/register") for _, url, _, _ in calls)
