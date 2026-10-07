"""Offline inference verifies provenance and never publishes partial snapshots."""
import builtins
import hashlib
import json
from types import SimpleNamespace

import pytest

from scripts import routing_shadow_worker as worker
from services.routing_shadow import observe_selection


@pytest.fixture
def inputs(tmp_path, monkeypatch):
    now = 1_800_000_000
    monkeypatch.setattr(worker.time, "time", lambda: now)
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir(mode=0o700)
    telemetry = tmp_path / "telemetry.json"
    output = tmp_path / "snapshot.json"
    data = {"schema_version": 1, "recorded_at": now,
            "measurement_method": worker.MEASUREMENT_METHOD,
            "perspective": worker.MEASUREMENT_PERSPECTIVE, "candidates": [
        {"server_id": "node-a", "measured_at": now, "source": "measured", "features": [40, .01, 3, .6]},
        {"server_id": "node-b", "measured_at": now, "source": "measured", "features": [20, 0, 2, .2]},
    ]}

    def save():
        telemetry.write_text(json.dumps(data))
        telemetry.chmod(0o600)

    def manifest():
        value = {"schema_version": 1, "model_origin": "synthetic_simulator", "model_version": "test-v1",
                 "feature_names": list(worker.FEATURES), "sha256": {
                     name: hashlib.sha256((artifacts / name).read_bytes()).hexdigest()
                     for name in ("model.json", "policy.json")}}
        path = artifacts / "manifest.json"
        path.write_text(json.dumps(value))
        path.chmod(0o600)
        return value

    for name, value in (("model.json", {"dummy": "untrained"}), ("policy.json", {"schema_version": 1, "q_table": {}})):
        path = artifacts / name
        path.write_text(json.dumps(value))
        path.chmod(0o600)
    save()
    manifest()
    return SimpleNamespace(artifacts=artifacts, telemetry=telemetry, output=output,
                           data=data, save=save, manifest=manifest, now=now)


def cli(inputs):
    return worker.main(["--artifacts", str(inputs.artifacts), "--telemetry", str(inputs.telemetry), "--output", str(inputs.output)])


@pytest.mark.parametrize("change", [
    lambda d: d.update(schema_version=True),
    lambda d: d.update(recorded_at=1_799_999_879),
    lambda d: d.update(recorded_at=1_800_000_006),
    lambda d: d.pop("measurement_method"),
    lambda d: d.pop("perspective"),
    lambda d: d.update(measurement_method="database_health_metrics"),
    lambda d: d.update(perspective="client_to_server"),
    lambda d: d.update(candidates=[]),
    lambda d: d["candidates"][0].update(source="estimated"),
    lambda d: d["candidates"][0].update(measured_at=1_799_999_879),
    lambda d: d["candidates"][0].update(features=[1, 0, 2]),
    lambda d: d["candidates"][0].update(features=[-1, 0, 2, .2]),
    lambda d: d["candidates"][0].update(features=[1, 1.01, 2, .2]),
    lambda d: d["candidates"][0].update(features=[1, 0, 5001, .2]),
    lambda d: d["candidates"][0].update(features=[1, 0, 2, 1.1]),
    lambda d: d["candidates"][0].update(features=[1, 0, 2, float("nan")]),
    lambda d: d["candidates"][0].update(features=[True, 0, 2, .2]),
    lambda d: d["candidates"].append(d["candidates"][0].copy()),
])
def test_invalid_measurements_do_not_publish(inputs, change, capsys):
    inputs.output.write_text("existing")
    change(inputs.data)
    inputs.save()
    assert cli(inputs) == 1
    assert inputs.output.read_text() == "existing"
    assert json.loads(capsys.readouterr().out)["reason"] == "invalid_or_unavailable_input"


@pytest.mark.parametrize("name", ["model.json", "policy.json", "manifest.json"])
def test_missing_artifact_keeps_existing_output(inputs, name):
    (inputs.artifacts / name).unlink()
    inputs.output.write_text("existing")
    assert cli(inputs) == 1
    assert inputs.output.read_text() == "existing"


@pytest.mark.parametrize("name", ["model.json", "policy.json"])
def test_hash_mismatch_is_rejected_before_inference(inputs, name):
    (inputs.artifacts / name).write_text('{"corrupted":true}')
    with pytest.raises(ValueError, match="artifact_hash_mismatch"):
        worker.build_snapshot(inputs.artifacts, inputs.telemetry)


@pytest.mark.parametrize("change", [
    lambda d: d.update(feature_names=list(reversed(worker.FEATURES))),
    lambda d: d.update(model_origin="real_fleet"),
    lambda d: d.update(model_version="bad\nprivate"),
    lambda d: d.update(schema_version=2),
])
def test_model_metadata_parity_required(inputs, change):
    path = inputs.artifacts / "manifest.json"
    data = json.loads(path.read_text())
    change(data)
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError):
        worker.build_snapshot(inputs.artifacts, inputs.telemetry)


def test_corrupt_artifact_is_sanitized(inputs, capsys):
    (inputs.artifacts / "model.json").write_text("secret-corrupt-payload")
    assert cli(inputs) == 1
    out = capsys.readouterr().out
    assert "secret" not in out
    assert str(inputs.artifacts) not in out
    assert not inputs.output.exists()


def test_missing_optional_dependency_keeps_existing_output(inputs, monkeypatch):
    original = builtins.__import__
    def importing(name, *args, **kwargs):
        if name == "xgboost":
            raise ImportError("private-dependency-detail")
        return original(name, *args, **kwargs)
    monkeypatch.setattr(builtins, "__import__", importing)
    inputs.output.write_text("existing")
    assert cli(inputs) == 1
    assert inputs.output.read_text() == "existing"


def test_atomic_replacement_failure_preserves_previous_snapshot(inputs, monkeypatch):
    inputs.output.write_text("existing")
    def fail(*args):
        raise OSError("replace rejected")
    monkeypatch.setattr(worker.os, "replace", fail)
    with pytest.raises(OSError):
        worker.write_snapshot(inputs.output, {"schema_version": 1})
    assert inputs.output.read_text() == "existing"
    assert not list(inputs.output.parent.glob(".routing-snapshot-*"))


def test_public_directory_and_output_symlink_rejected(inputs):
    public = inputs.output.parent / "public"
    public.mkdir(mode=0o755)
    with pytest.raises(ValueError, match="output_directory_not_private"):
        worker.write_snapshot(public / "snapshot.json", {})
    inputs.output.symlink_to(inputs.telemetry)
    with pytest.raises(ValueError, match="output_symlink"):
        worker.write_snapshot(inputs.output, {})


def test_untrained_json_is_rejected(inputs):
    pytest.importorskip("xgboost")
    assert cli(inputs) == 1
    assert not inputs.output.exists()


def test_cpu_inference_to_real_runtime_contract(inputs, monkeypatch, capsys):
    xgb = pytest.importorskip("xgboost")
    np = pytest.importorskip("numpy")
    model = xgb.XGBRegressor(n_estimators=3, max_depth=2, n_jobs=1, device="cpu")
    model.fit(np.asarray([[40,.01,3,.6],[20,0,2,.2],[100,.1,10,.9],[10,0,1,.1]]), np.asarray([.4,.8,.1,.9]))
    model.save_model(inputs.artifacts / "model.json")
    (inputs.artifacts / "model.json").chmod(0o600)
    inputs.manifest()
    assert cli(inputs) == 0
    snapshot = json.loads(inputs.output.read_text())
    assert inputs.output.stat().st_mode & 0o777 == 0o600
    assert snapshot["recorded_at"] == inputs.data["recorded_at"]
    assert snapshot["measurement_method"] == worker.MEASUREMENT_METHOD
    assert snapshot["perspective"] == worker.MEASUREMENT_PERSPECTIVE
    assert [row["features"] for row in snapshot["candidates"]] == [row["features"] for row in inputs.data["candidates"]]
    assert snapshot["model_origin"] == "synthetic_simulator"
    monkeypatch.setenv("SECUREWAVE_ROUTING_SHADOW", "shadow")
    monkeypatch.setenv("SECUREWAVE_ROUTING_SNAPSHOT", str(inputs.output))
    monkeypatch.setenv("SECUREWAVE_ROUTING_POLICY", str(inputs.artifacts / "policy.json"))
    servers = [SimpleNamespace(server_id=row["server_id"]) for row in inputs.data["candidates"]]
    assert observe_selection(servers, servers[0]).status == "observed"
    assert "node-a" not in capsys.readouterr().out


def test_trained_artifact_round_trip(inputs):
    pytest.importorskip("xgboost")
    from ml.train_routing import train
    train(inputs.artifacts, seed=42, episodes=8)
    assert cli(inputs) == 0
    snapshot = json.loads(inputs.output.read_text())
    assert snapshot["model_version"] == "routing-simulator-v1-seed42-episodes8"
    assert len(snapshot["candidates"]) == 2


@pytest.mark.parametrize("prediction", [-.1, 1.1])
def test_prediction_outside_normalized_utility_does_not_publish(inputs, monkeypatch, prediction):
    xgb = pytest.importorskip("xgboost")
    np = pytest.importorskip("numpy")
    class InvalidBooster:
        def __init__(self, **kwargs):
            pass
        def load_model(self, raw):
            pass
        def set_param(self, values):
            pass
        def num_features(self):
            return 4
        def predict(self, matrix):
            return np.asarray([prediction, .5])
    monkeypatch.setattr(xgb, "Booster", InvalidBooster)
    inputs.output.write_text("existing")
    assert cli(inputs) == 1
    assert inputs.output.read_text() == "existing"
