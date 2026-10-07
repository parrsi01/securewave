import json
from types import SimpleNamespace

import pytest
from scripts.collect_routing_telemetry import collect, inventory, parse_measurement, write_private

PING = "5 packets transmitted, 4 received, 20% packet loss\nrtt min/avg/max/mdev = 10.0/20.0/30.0/5.0 ms"
LOAD = "0.50 0.10 0.01 1/100 99\n2\n"


def test_real_probe_units():
    assert parse_measurement(PING, LOAD) == [20, 0.2, 5, 0.25]


@pytest.mark.parametrize("ping,load", [("100% packet loss", LOAD), (PING, "nan 0 0 0 0 2"),
                                     (PING, "1 0 0 0 0 0"), (PING.replace("20%", "120%"), LOAD)])
def test_missing_or_invalid_measurement_rejected(ping, load):
    with pytest.raises(ValueError):
        parse_measurement(ping, load)


def test_inventory_rejects_aliases_and_non_ip_targets(tmp_path):
    path = tmp_path / "fleet.json"
    def save(rows):
        path.write_text(json.dumps({"schema_version": 1, "servers": rows}))
        path.chmod(0o600)
    save([{"server_id": "real", "address": "203.0.113.1"}])
    assert len(inventory(path)) == 1
    save([{"server_id": "real", "address": "203.0.113.1"},
          {"server_id": "alias", "address": "203.0.113.1"}])
    with pytest.raises(ValueError):
        inventory(path)
    save([{"server_id": "real", "address": "-bad-option"}])
    with pytest.raises(ValueError):
        inventory(path)


def test_collection_uses_bounded_readonly_commands(tmp_path):
    calls = []
    def run(args, **kwargs):
        calls.append((args, kwargs))
        return SimpleNamespace(returncode=0, stdout=PING if args[0] == "ping" else LOAD)
    doc = collect([{"server_id": "real", "address": "203.0.113.1"}], tmp_path / "key", runner=run)
    assert doc["candidates"][0]["source"] == "measured"
    assert all(call[1]["timeout"] == 10 for call in calls)
    assert "StrictHostKeyChecking=yes" in calls[1][0]
    assert calls[1][0][-1] == "LC_ALL=C cat /proc/loadavg; getconf _NPROCESSORS_ONLN"


def test_atomic_private_output(tmp_path):
    tmp_path.chmod(0o700)
    path = tmp_path / "data.json"
    write_private(path, {"ok": True})
    assert path.stat().st_mode & 0o777 == 0o600
    with pytest.raises(ValueError):
        write_private(path, {"bad": float("nan")})
    assert json.loads(path.read_text()) == {"ok": True}


def test_public_output_directory_rejected(tmp_path):
    tmp_path.chmod(0o755)
    with pytest.raises(ValueError):
        write_private(tmp_path / "data.json", {})
