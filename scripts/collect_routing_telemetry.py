"""Measure an operator-approved fleet, outside API requests and model training.

ICMP round-trip statistics are path probes, not decrypted traffic or application
QoS. Load is the server's one-minute run queue divided by online CPU count.
Inventory contains only {schema_version:1, servers:[{server_id,address}]}.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from services.routing_shadow import _identifier, _read_json


def inventory(path: Path) -> list[dict]:
    doc, _ = _read_json(str(path), 64 * 1024, private=True)
    if type(doc.get("schema_version")) is not int or doc["schema_version"] != 1:
        raise ValueError("invalid_inventory")
    rows = doc.get("servers")
    if not isinstance(rows, list) or not 1 <= len(rows) <= 32:
        raise ValueError("invalid_inventory")
    ids, addresses, approved = set(), set(), []
    for row in rows:
        identifier = _identifier(row["server_id"])
        address = str(ipaddress.ip_address(row["address"]))
        if identifier in ids or address in addresses:
            # Aliases must not masquerade as independent physical servers.
            raise ValueError("duplicate_inventory")
        ids.add(identifier)
        addresses.add(address)
        approved.append({"server_id": identifier, "address": address})
    return approved


def parse_measurement(ping: str, load: str) -> list[float]:
    loss_match = re.search(r"([\d.]+)% packet loss", ping)
    rtt_match = re.search(r"(?:rtt|round-trip).*?= ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+) ms", ping)
    if not loss_match or not rtt_match:
        raise ValueError("unavailable_measurement")
    fields = load.split()
    if len(fields) != 6:
        raise ValueError("invalid_load")
    queue, cpus = float(fields[0]), int(fields[-1])
    latency, jitter = float(rtt_match[2]), float(rtt_match[4])
    packet_loss = float(loss_match[1]) / 100
    if cpus < 1 or queue < 0 or not math.isfinite(queue):
        raise ValueError("invalid_load")
    result = [latency, packet_loss, jitter, min(1.0, queue / cpus)]
    if any(not math.isfinite(v) or not 0 <= v <= upper
           for v, upper in zip(result, (5000, 1, 5000, 1))):
        raise ValueError("invalid_measurement")
    return result


def collect(rows: list[dict], ssh_key: Path, ssh_user: str = "root", runner=subprocess.run) -> dict:
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", ssh_user):
        raise ValueError("invalid_ssh_user")
    candidates = []
    for row in rows:
        address = str(ipaddress.ip_address(row["address"]))
        # With a global -w deadline some iputils versions keep transmitting
        # until enough replies arrive. Per-reply -W keeps the sample at five.
        probe = runner(["ping", "-n", "-c", "5", "-i", "0.2", "-W", "1", address],
                       capture_output=True, text=True, timeout=10,
                       env={**os.environ, "LC_ALL": "C"})
        if probe.returncode not in (0, 1):
            raise ValueError("probe_failed")
        host = runner(["ssh", "-i", str(ssh_key.resolve()), "-o", "BatchMode=yes",
                       "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5",
                       f"{ssh_user}@{address}", "LC_ALL=C cat /proc/loadavg; getconf _NPROCESSORS_ONLN"],
                      capture_output=True, text=True, timeout=10)
        if host.returncode != 0:
            raise ValueError("load_probe_failed")
        features = parse_measurement(probe.stdout, host.stdout)
        candidates.append({"server_id": _identifier(row["server_id"]),
                           "measured_at": time.time(), "source": "measured", "features": features})
    return {"schema_version": 1, "recorded_at": time.time(), "candidates": candidates,
            "measurement_method": "icmp_rtt_mdev_loss_and_loadavg_per_online_cpu",
            "perspective": "collector_host_to_server"}


def write_private(path: Path, document: dict) -> None:
    parent = path.parent
    info = parent.stat()
    if parent.is_symlink() or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise ValueError("output_directory_not_private")
    if path.is_symlink():
        raise ValueError("output_symlink")
    raw = (json.dumps(document, allow_nan=False, sort_keys=True) + "\n").encode()
    if len(raw) > 64 * 1024:
        raise ValueError("oversized_output")
    fd, temp_path = tempfile.mkstemp(prefix=".routing-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--ssh-key", type=Path, required=True)
    parser.add_argument("--ssh-user", default="root")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        doc = collect(inventory(args.inventory), args.ssh_key, args.ssh_user)
        write_private(args.output, doc)
        print(json.dumps({"status": "measured", "approved_endpoints": len(doc["candidates"])}))
        return 0
    except Exception:
        print('{"status":"unavailable_measurement"}', file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
