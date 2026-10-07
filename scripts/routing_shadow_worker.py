#!/usr/bin/env python3
"""Offline CPU inference for fresh routing measurements; never controls VPNs.

Run as the same account that reads snapshots in the API. The output directory
must already be private. No telemetry collection, network or database access
occurs in this worker.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import time

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.routing_policy import FEATURES
from services.routing_shadow import (
    MEASUREMENT_METHOD, MEASUREMENT_PERSPECTIVE,
    _identifier, _number, _read_json, _timestamp,
)

MAX_BYTES = 64 * 1024


def _schema(document: dict) -> None:
    if type(document.get("schema_version")) is not int or document["schema_version"] != 1:
        raise ValueError("invalid_schema")


def build_snapshot(artifacts: Path, telemetry: Path) -> dict:
    """Verify measurements and trusted artifact bytes before optional imports."""
    observations, _ = _read_json(str(telemetry), MAX_BYTES, private=True)
    _schema(observations)
    # A database health timestamp cannot establish measured feature provenance:
    # the deployed legacy monitor estimates jitter/loss and simulates CPU load.
    if observations.get("measurement_method") != MEASUREMENT_METHOD or observations.get("perspective") != MEASUREMENT_PERSPECTIVE:
        raise ValueError("invalid_measurement_provenance")
    now = time.time()
    _timestamp(observations.get("recorded_at"), now)
    rows = observations.get("candidates")
    if not isinstance(rows, list) or not 1 <= len(rows) <= 256:
        raise ValueError("invalid_candidates")
    ids: set[str] = set()
    checked = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("invalid_candidate")
        server_id = _identifier(row.get("server_id"))
        if server_id in ids or row.get("source") != "measured":
            raise ValueError("unmeasured_or_duplicate_candidate")
        ids.add(server_id)
        _timestamp(row.get("measured_at"), now)
        features = row.get("features")
        if not isinstance(features, list) or len(features) != len(FEATURES):
            raise ValueError("invalid_features")
        for value, upper in zip(features, (5000, 1, 5000, 1)):
            _number(value, 0, upper)
        checked.append({"server_id": server_id, "measured_at": row["measured_at"],
                        "source": "measured", "features": features.copy()})

    manifest, _ = _read_json(str(artifacts / "manifest.json"), 256 * 1024, private=True)
    _schema(manifest)
    if manifest.get("feature_names") != list(FEATURES) or manifest.get("model_origin") != "synthetic_simulator":
        raise ValueError("invalid_model_metadata")
    version = _identifier(manifest.get("model_version"))
    hashes = manifest.get("sha256")
    if not isinstance(hashes, dict):
        raise ValueError("invalid_hashes")
    model_document, model_raw = _read_json(str(artifacts / "model.json"), 8 * 1024 * 1024, private=True)
    policy, policy_raw = _read_json(str(artifacts / "policy.json"), 256 * 1024, private=True)
    del model_document
    for name, raw in (("model.json", model_raw), ("policy.json", policy_raw)):
        if hashes.get(name) != hashlib.sha256(raw).hexdigest():
            raise ValueError("artifact_hash_mismatch")
    _schema(policy)
    q_table = policy.get("q_table")
    if not isinstance(q_table, dict):
        raise ValueError("invalid_policy")
    for key, values in q_table.items():
        if not isinstance(key, str) or len(key) > 512 or not isinstance(values, list) or len(values) != 3:
            raise ValueError("invalid_policy")
        for value in values:
            _number(value, -1e12, 1e12)

    # Heavy native packages are imported only in this separate offline worker.
    import numpy as np
    import xgboost as xgb

    booster = xgb.Booster(params={"nthread": 1, "device": "cpu"})
    booster.load_model(bytearray(model_raw))
    booster.set_param({"nthread": 1, "device": "cpu"})
    if booster.num_features() != len(FEATURES):
        raise ValueError("invalid_model_features")
    matrix = xgb.DMatrix(np.asarray([row["features"] for row in checked], dtype=np.float32), nthread=1)
    predictions = booster.predict(matrix)
    if predictions.ndim != 1 or len(predictions) != len(checked):
        raise ValueError("invalid_prediction_shape")
    now = time.time()
    _timestamp(observations["recorded_at"], now)
    for row, prediction in zip(checked, predictions):
        _timestamp(row["measured_at"], now)
        row["predicted_utility"] = _number(float(prediction), 0, 1)
    return {"schema_version": 1, "model_origin": "synthetic_simulator", "model_version": version,
            "recorded_at": observations["recorded_at"], "policy_sha256": hashlib.sha256(policy_raw).hexdigest(),
            "measurement_method": observations["measurement_method"], "perspective": observations["perspective"],
            "candidates": checked}


def write_snapshot(output: Path, snapshot: dict) -> None:
    """Replace a complete mode-0600 snapshot atomically, preserving old output on error."""
    parent = output.parent
    info = parent.stat()
    if parent.is_symlink() or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise ValueError("output_directory_not_private")
    if output.is_symlink():
        raise ValueError("output_symlink")
    raw = (json.dumps(snapshot, allow_nan=False, sort_keys=True) + "\n").encode()
    if len(raw) > MAX_BYTES:
        raise ValueError("snapshot_too_large")
    descriptor, temporary = tempfile.mkstemp(prefix=".routing-snapshot-", dir=parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", required=True, type=Path)
    parser.add_argument("--telemetry", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        snapshot = build_snapshot(args.artifacts, args.telemetry)
        write_snapshot(args.output, snapshot)
    except Exception:
        # Raw exceptions can reveal private paths or supplied telemetry.
        print(json.dumps({"status": "unavailable", "reason": "invalid_or_unavailable_input"}))
        return 1
    print(json.dumps({"status": "snapshot_ready", "candidate_count": len(snapshot["candidates"]),
                      "model_origin": snapshot["model_origin"], "model_version": snapshot["model_version"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
