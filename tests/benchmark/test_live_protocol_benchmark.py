from __future__ import annotations

import json

from dev_tools.sandbox.benchmark.live_protocol_benchmark import run_live_protocol_benchmark


def test_live_protocol_benchmark_publishes_website_summary(tmp_path, monkeypatch):
    monkeypatch.setattr(
        "dev_tools.sandbox.benchmark.live_protocol_benchmark._resolve_interface",
        lambda protocol, explicit: explicit or {"wireguard": "wg0", "openvpn": "tun0", "ikev2": None}[protocol],
    )
    monkeypatch.setattr(
        "dev_tools.sandbox.benchmark.live_protocol_benchmark._measure_public_ip",
        lambda interface: type("Metric", (), {
            "status": "pass" if interface != "tun0" else "fail",
            "value": None,
            "reason": None if interface != "tun0" else "curl_exit_28",
            "source": "curl",
            "evidence": "203.0.113.10" if interface != "tun0" else "curl ...",
        })(),
    )
    monkeypatch.setattr(
        "dev_tools.sandbox.benchmark.live_protocol_benchmark._measure_latency",
        lambda interface, ping_target: type("Metric", (), {
            "status": "pass" if interface != "tun0" else "fail",
            "value": 12.5 if interface is None else (20.0 if interface == "wg0" else None),
            "reason": None if interface != "tun0" else "ping_exit_2",
            "source": "ping",
            "evidence": "ping ...",
        })(),
    )
    monkeypatch.setattr(
        "dev_tools.sandbox.benchmark.live_protocol_benchmark._measure_download",
        lambda interface, download_url, bytes_to_fetch: type("Metric", (), {
            "status": "pass" if interface != "tun0" else "fail",
            "value": 100.0 if interface is None else (84.0 if interface == "wg0" else None),
            "reason": None if interface != "tun0" else "curl_exit_7",
            "source": "curl",
            "evidence": "curl ...",
        })(),
    )
    monkeypatch.setattr(
        "dev_tools.sandbox.benchmark.live_protocol_benchmark._measure_upload",
        lambda interface, host, port, duration: type("Metric", (), {
            "status": "unavailable" if host is None else "pass",
            "value": None if host is None else 50.0,
            "reason": "iperf_host_not_configured" if host is None else None,
            "source": None if host is None else "iperf3",
            "evidence": None if host is None else "iperf3 ...",
        })(),
    )

    output_root = tmp_path / "artifacts"
    publish_path = tmp_path / "static" / "data" / "performance_benchmarks.json"
    payload = run_live_protocol_benchmark(
        output_root=output_root,
        publish_path=publish_path,
        download_url="https://example.test/file.bin",
        iperf_host=None,
    )

    published = json.loads(publish_path.read_text(encoding="utf-8"))
    assert published["baseline"]["download_mbps"] == 100.0
    assert published["protocols"]["wireguard"]["download_retention_pct"] == 84.0
    assert published["protocols"]["openvpn"]["status"] == "fail"
    assert published["protocols"]["ikev2"]["status"] == "unavailable"
    assert payload["website"] == published
