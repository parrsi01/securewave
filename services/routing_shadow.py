"""Read an offline routing recommendation without influencing VPN selection.

No ML package, network request, database mutation or training occurs here.
Snapshots must contain fresh measured observations; simulator-trained models
remain explicitly labelled as such even when their inputs are measurements.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import logging
import math
import os
from pathlib import Path
import re
import stat
import time
from typing import Any, Sequence


logger = logging.getLogger(__name__)
_MAX_SNAPSHOT_BYTES = 64 * 1024
_MAX_POLICY_BYTES = 256 * 1024
_MAX_AGE_SECONDS = 120
_FUTURE_TOLERANCE_SECONDS = 5
_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.+-]{0,127}$")
MEASUREMENT_METHOD = "icmp_rtt_mdev_loss_and_loadavg_per_online_cpu"
MEASUREMENT_PERSPECTIVE = "collector_host_to_server"


@dataclass(frozen=True)
class ShadowDecision:
    status: str
    reason: str
    baseline_server_id: str | None = None
    recommended_server_id: str | None = None
    model_origin: str | None = None
    model_version: str | None = None


def _number(value: Any, lower: float, upper: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("invalid_number")
    result = float(value)
    if not math.isfinite(result) or not lower <= result <= upper:
        raise ValueError("invalid_number")
    return result


def _timestamp(value: Any, now: float) -> float:
    return _number(value, now - _MAX_AGE_SECONDS, now + _FUTURE_TOLERANCE_SECONDS)


def _identifier(value: Any) -> str:
    if not isinstance(value, str) or not _IDENTIFIER.fullmatch(value):
        raise ValueError("invalid_identifier")
    return value


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate_key")
        result[key] = value
    return result


def _read_json(path: str, max_bytes: int, *, private: bool = False) -> tuple[dict, bytes]:
    # O_NONBLOCK and regular-file validation prevent pipes/devices from waiting
    # inside an API request. O_NOFOLLOW rejects a final-component symlink.
    descriptor = os.open(Path(path), os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > max_bytes:
            raise ValueError("invalid_file")
        if private and (info.st_uid != os.geteuid() or info.st_mode & 0o077):
            raise ValueError("snapshot_not_private")
        raw = handle.read(max_bytes + 1)
        if len(raw) > max_bytes:
            raise ValueError("file_too_large")
    value = json.loads(raw, object_pairs_hook=_reject_duplicate_keys)
    if not isinstance(value, dict):
        raise ValueError("invalid_document")
    return value, raw


def _observe(candidates: Sequence[Any], baseline: Any, explicit: bool) -> ShadowDecision:
    mode = os.getenv("SECUREWAVE_ROUTING_SHADOW", "off").strip().lower()
    if mode == "off":
        return ShadowDecision("off", "disabled")
    if mode != "shadow":
        return ShadowDecision("skipped", "invalid_mode")
    baseline_id = _identifier(getattr(baseline, "server_id", None))
    if explicit:
        return ShadowDecision("skipped", "explicit_selection", baseline_id)
    ids = [_identifier(getattr(server, "server_id", None)) for server in candidates]
    if len(ids) != len(set(ids)) or baseline_id not in ids:
        return ShadowDecision("skipped", "invalid_candidates", baseline_id)
    if len(ids) <= 1:
        return ShadowDecision("skipped", "no_alternative", baseline_id)
    snapshot_path = os.getenv("SECUREWAVE_ROUTING_SNAPSHOT", "")
    policy_path = os.getenv("SECUREWAVE_ROUTING_POLICY", "")
    if not snapshot_path or not policy_path:
        return ShadowDecision("skipped", "missing_artifact", baseline_id)

    snapshot, _ = _read_json(snapshot_path, _MAX_SNAPSHOT_BYTES, private=True)
    if type(snapshot.get("schema_version")) is not int or snapshot["schema_version"] != 1:
        raise ValueError("invalid_schema")
    if snapshot.get("model_origin") != "synthetic_simulator":
        raise ValueError("invalid_model_origin")
    if snapshot.get("measurement_method") != MEASUREMENT_METHOD or snapshot.get("perspective") != MEASUREMENT_PERSPECTIVE:
        raise ValueError("invalid_measurement_provenance")
    version = _identifier(snapshot.get("model_version"))
    now = time.time()
    _timestamp(snapshot.get("recorded_at"), now)
    digest = snapshot.get("policy_sha256")
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("invalid_policy_hash")
    policy, policy_raw = _read_json(policy_path, _MAX_POLICY_BYTES)
    if hashlib.sha256(policy_raw).hexdigest() != digest:
        raise ValueError("policy_hash_mismatch")
    if type(policy.get("schema_version")) is not int or policy["schema_version"] != 1:
        raise ValueError("invalid_policy_schema")
    table = policy.get("q_table")
    if not isinstance(table, dict):
        raise ValueError("invalid_q_table")
    for key, values in table.items():
        if not isinstance(key, str) or len(key) > 512 or not isinstance(values, list) or len(values) != 3:
            raise ValueError("invalid_q_table")
        for value in values:
            _number(value, -1e12, 1e12)

    rows = snapshot.get("candidates")
    if not isinstance(rows, list) or len(rows) > 256:
        raise ValueError("invalid_observations")
    measured: dict[str, tuple[float, float]] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("invalid_observation")
        server_id = _identifier(row.get("server_id"))
        if server_id in measured:
            raise ValueError("duplicate_observation")
        if row.get("source") != "measured":
            raise ValueError("unmeasured_observation")
        _timestamp(row.get("measured_at"), now)
        features = row.get("features")
        if not isinstance(features, list) or len(features) != 4:
            raise ValueError("invalid_features")
        values = [_number(value, 0, upper) for value, upper in zip(features, (5000, 1, 5000, 1))]
        prediction = _number(row.get("predicted_utility"), 0, 1)
        measured[server_id] = (prediction, values[3])
    # Every current eligible candidate needs a measured observation. Choosing
    # among a smaller accidental subset would conceal missing telemetry.
    if any(server_id not in measured for server_id in ids):
        return ShadowDecision("skipped", "missing_telemetry", baseline_id)
    from ml.routing_policy import recommend_index

    predictions = [measured[server_id][0] for server_id in ids]
    loads = [measured[server_id][1] for server_id in ids]
    index, reason = recommend_index(predictions, loads, ids.index(baseline_id), table)
    if type(index) is not int or not 0 <= index < len(ids):
        raise ValueError("invalid_recommendation")
    if not isinstance(reason, str) or not re.fullmatch(r"[A-Za-z0-9_ -]{1,64}", reason):
        raise ValueError("invalid_reason")
    return ShadowDecision("observed", reason, baseline_id, ids[index], "synthetic_simulator", version)


def observe_selection(candidates: Sequence[Any], baseline_server: Any, explicit: bool = False) -> ShadowDecision:
    """Return advisory evidence only; all failures leave normal routing intact."""
    try:
        decision = _observe(candidates, baseline_server, explicit)
    except Exception:
        # Do not expose exception text: paths/artifacts can contain private data.
        decision = ShadowDecision("skipped", "invalid_or_unavailable_artifact")
    if decision.status != "off":
        try:
            logger.info(
                "routing_shadow status=%s reason=%s baseline=%s recommendation=%s model_origin=%s model_version=%s",
                decision.status, decision.reason, decision.baseline_server_id,
                decision.recommended_server_id, decision.model_origin, decision.model_version,
            )
        except Exception:
            pass  # Broken logging must not become a VPN provisioning failure.
    return decision
