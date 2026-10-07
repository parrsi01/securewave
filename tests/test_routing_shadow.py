"""Routing shadow cannot change provisioning or consume invented telemetry."""
from dataclasses import FrozenInstanceError
import hashlib
import json
import os
import subprocess
import sys
from types import SimpleNamespace

import pytest

from services import routing_shadow as shadow


@pytest.fixture
def artifacts(tmp_path, monkeypatch):
    now = 1_800_000_000
    monkeypatch.setattr(shadow.time, "time", lambda: now)
    candidates = [SimpleNamespace(server_id="node-a"), SimpleNamespace(server_id="node-b")]
    policy = tmp_path / "policy.json"
    policy.write_text(json.dumps({"schema_version": 1, "q_table": {}}))
    snapshot = tmp_path / "snapshot.json"
    data = {
        "schema_version": 1,
        "model_origin": "synthetic_simulator",
        "model_version": "routing-simulator-v1",
        "measurement_method": shadow.MEASUREMENT_METHOD,
        "perspective": shadow.MEASUREMENT_PERSPECTIVE,
        "recorded_at": now,
        "policy_sha256": hashlib.sha256(policy.read_bytes()).hexdigest(),
        "candidates": [
            {"server_id": "node-a", "measured_at": now, "source": "measured", "features": [40, 0.01, 3, 0.6], "predicted_utility": 0.4},
            {"server_id": "node-b", "measured_at": now, "source": "measured", "features": [20, 0, 2, 0.2], "predicted_utility": 0.8},
        ],
    }

    def save():
        snapshot.write_text(json.dumps(data))
        snapshot.chmod(0o600)

    save()
    monkeypatch.setenv("SECUREWAVE_ROUTING_SHADOW", "shadow")
    monkeypatch.setenv("SECUREWAVE_ROUTING_SNAPSHOT", str(snapshot))
    monkeypatch.setenv("SECUREWAVE_ROUTING_POLICY", str(policy))
    return SimpleNamespace(candidates=candidates, baseline=candidates[0], policy=policy, snapshot=snapshot, data=data, save=save, now=now)


def observe(artifacts, **kwargs):
    return shadow.observe_selection(artifacts.candidates, artifacts.baseline, **kwargs)


def test_off_has_zero_artifact_access(monkeypatch):
    monkeypatch.delenv("SECUREWAVE_ROUTING_SHADOW", raising=False)
    monkeypatch.setattr(shadow, "_read_json", lambda *_args, **_kwargs: pytest.fail("read when off"))
    assert shadow.observe_selection([], None).status == "off"


def test_cold_api_import_never_loads_native_ml_dependencies():
    result = subprocess.run(
        [sys.executable, "-c", "import sys; import services.routing_shadow; assert not {'numpy','xgboost','pandas','sklearn'} & set(sys.modules)"],
        check=False, capture_output=True, timeout=5,
    )
    assert result.returncode == 0, result.stderr.decode()


def test_observer_is_immutable_advisory_only(artifacts):
    before = list(artifacts.candidates)
    decision = observe(artifacts)
    assert decision.status == "observed"
    assert decision.baseline_server_id == "node-a"
    assert decision.recommended_server_id == "node-b"
    assert decision.model_origin == "synthetic_simulator"
    assert artifacts.candidates == before
    assert artifacts.baseline is before[0]
    with pytest.raises(FrozenInstanceError):
        decision.recommended_server_id = "node-a"


def test_explicit_selection_does_not_read_artifacts(artifacts, monkeypatch):
    monkeypatch.setattr(shadow, "_read_json", lambda *_args, **_kwargs: pytest.fail("explicit selection read"))
    assert observe(artifacts, explicit=True).reason == "explicit_selection"


def test_single_candidate_does_not_read_artifacts(artifacts, monkeypatch):
    monkeypatch.setattr(shadow, "_read_json", lambda *_args, **_kwargs: pytest.fail("single node read"))
    decision = shadow.observe_selection([artifacts.baseline], artifacts.baseline)
    assert decision.reason == "no_alternative"


@pytest.mark.parametrize("change", [
    lambda d: d.update(recorded_at=1_799_999_879),
    lambda d: d.update(recorded_at=1_800_000_006),
    lambda d: d.update(schema_version=True),
    lambda d: d.update(model_origin="real_fleet"),
    lambda d: d.pop("measurement_method"),
    lambda d: d.pop("perspective"),
    lambda d: d.update(measurement_method="database_health_metrics"),
    lambda d: d.update(perspective="client_to_server"),
    lambda d: d.update(model_version="bad\nprivate token"),
    lambda d: d.update(policy_sha256="0" * 64),
    lambda d: d["candidates"][0].update(measured_at=1_799_999_879),
    lambda d: d["candidates"][0].update(source="estimated"),
    lambda d: d["candidates"][0].update(source="simulated"),
    lambda d: d["candidates"][0].update(features=[10, 0, 2]),
    lambda d: d["candidates"][0].update(features=[5001, 0, 2, .2]),
    lambda d: d["candidates"][0].update(features=[10, 1.01, 2, .2]),
    lambda d: d["candidates"][0].update(features=[10, 0, 5001, .2]),
    lambda d: d["candidates"][0].update(features=[10, 0, 2, -1]),
    lambda d: d["candidates"][0].update(features=[float("nan"), 0, 2, .2]),
    lambda d: d["candidates"][0].update(features=[True, 0, 2, .2]),
    lambda d: d["candidates"][0].update(predicted_utility=float("inf")),
    lambda d: d["candidates"][0].update(predicted_utility=-0.1),
    lambda d: d["candidates"][0].update(predicted_utility=1.1),
    lambda d: d["candidates"].append(d["candidates"][0].copy()),
])
def test_invalid_or_stale_data_never_recommends(artifacts, change):
    change(artifacts.data)
    artifacts.save()
    decision = observe(artifacts)
    assert decision.status == "skipped"
    assert decision.recommended_server_id is None


def test_missing_candidate_measurement_skips(artifacts):
    artifacts.data["candidates"].pop()
    artifacts.save()
    assert observe(artifacts).reason == "missing_telemetry"


def test_extra_snapshot_server_cannot_be_chosen(artifacts):
    row = artifacts.data["candidates"][1].copy()
    row.update(server_id="ineligible-node", predicted_utility=.99)
    artifacts.data["candidates"].append(row)
    artifacts.save()
    assert observe(artifacts).recommended_server_id == "node-b"


@pytest.mark.parametrize("bad_policy", [
    {"schema_version": 1, "q_table": {"state": [0, 1]}},
    {"schema_version": 1, "q_table": {"state": [0, 1, float("nan")]}},
    {"schema_version": 1, "q_table": {"state": [0, True, 1]}},
    {"schema_version": 2, "q_table": {}},
])
def test_invalid_policy_skips_even_when_hash_matches(artifacts, bad_policy):
    artifacts.policy.write_text(json.dumps(bad_policy))
    artifacts.data["policy_sha256"] = hashlib.sha256(artifacts.policy.read_bytes()).hexdigest()
    artifacts.save()
    assert observe(artifacts).status == "skipped"


@pytest.mark.parametrize("failure", ["missing", "oversized", "symlink", "public", "pipe", "duplicate_keys"])
def test_artifact_failure_is_bounded_fail_open(artifacts, failure):
    if failure == "missing":
        artifacts.snapshot.unlink()
    elif failure == "oversized":
        artifacts.snapshot.write_bytes(b" " * (shadow._MAX_SNAPSHOT_BYTES + 1))
    elif failure == "symlink":
        artifacts.snapshot.unlink()
        artifacts.snapshot.symlink_to(artifacts.policy)
    elif failure == "public":
        artifacts.snapshot.chmod(0o644)
    elif failure == "pipe":
        artifacts.snapshot.unlink()
        os.mkfifo(artifacts.snapshot, 0o600)
    else:
        artifacts.snapshot.write_text('{"schema_version":1,"schema_version":2}')
    assert observe(artifacts).status == "skipped"


def test_freshness_boundaries_are_accepted(artifacts):
    artifacts.data["recorded_at"] = artifacts.now - 120
    artifacts.data["candidates"][0]["measured_at"] = artifacts.now + 5
    artifacts.save()
    assert observe(artifacts).status == "observed"


def test_observer_exception_and_logging_failure_are_contained(artifacts, monkeypatch):
    def fail(*_args, **_kwargs):
        raise RuntimeError("sensitive-example")
    monkeypatch.setattr(shadow, "_observe", fail)
    monkeypatch.setattr(shadow.logger, "info", fail)
    decision = observe(artifacts)
    assert decision.status == "skipped"
    assert "sensitive" not in repr(decision)


def test_logs_never_include_artifact_fields_or_user_identity(artifacts, caplog):
    artifacts.data.update(user_id="secret-user", access_token="secret-token")
    artifacts.save()
    with caplog.at_level("INFO", logger=shadow.__name__):
        observe(artifacts)
    assert "secret-user" not in caplog.text
    assert "secret-token" not in caplog.text
    assert str(artifacts.snapshot) not in caplog.text


def test_invalid_mode_reads_nothing(artifacts, monkeypatch):
    monkeypatch.setenv("SECUREWAVE_ROUTING_SHADOW", "active")
    monkeypatch.setattr(shadow, "_read_json", lambda *_args, **_kwargs: pytest.fail("invalid mode read"))
    assert observe(artifacts).reason == "invalid_mode"
