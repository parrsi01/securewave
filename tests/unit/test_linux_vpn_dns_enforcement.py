from __future__ import annotations

import os
import subprocess  # nosec B404
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "securewave_app/packaging/linux/securewave-wg-quick"


def _write_fake(binary: Path, body: str) -> None:
    binary.write_text("#!/usr/bin/env bash\nset -eu\n" + body, encoding="utf-8")
    binary.chmod(0o755)


def _environment(fake_bin: Path, trace: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:/usr/bin:/bin"
    env["TRACE_FILE"] = str(trace)
    return env


def test_openvpn_dns_uses_only_dedicated_link_and_route_only_domain(
    tmp_path: Path,
):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    trace = tmp_path / "trace"
    _write_fake(
        fake_bin / "resolvectl",
        'printf \'resolvectl %s\\n\' "$*" >> "$TRACE_FILE"\n',
    )

    result = subprocess.run(  # nosec B603
        [str(HELPER), "openvpn-dns-apply", "4:1.1.1.1", "6:2606:4700:4700::1111"],
        check=False,
        capture_output=True,
        text=True,
        env=_environment(fake_bin, trace),
    )

    assert result.returncode == 0, result.stderr
    assert trace.read_text(encoding="utf-8").splitlines() == [
        "resolvectl dns tun-securewave 1.1.1.1 2606:4700:4700::1111",
        "resolvectl domain tun-securewave ~.",
    ]


def test_openvpn_dns_rejects_untagged_or_command_shaped_values(tmp_path: Path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    trace = tmp_path / "trace"
    _write_fake(
        fake_bin / "resolvectl",
        "printf 'unexpected\\n' >> \"$TRACE_FILE\"\n",
    )

    for address in ("1.1.1.1", "4:1.1.1.1;id", "6:2606:4700::1111$(id)"):
        result = subprocess.run(  # nosec B603
            [str(HELPER), "openvpn-dns-apply", address],
            check=False,
            capture_output=True,
            text=True,
            env=_environment(fake_bin, trace),
        )
        assert result.returncode == 64
    assert not trace.exists()


def test_openvpn_dns_revert_is_fixed_to_securewave_link(tmp_path: Path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    trace = tmp_path / "trace"
    _write_fake(
        fake_bin / "resolvectl",
        'printf \'resolvectl %s\\n\' "$*" >> "$TRACE_FILE"\n',
    )

    result = subprocess.run(  # nosec B603
        [str(HELPER), "openvpn-dns-revert"],
        check=False,
        capture_output=True,
        text=True,
        env=_environment(fake_bin, trace),
    )

    assert result.returncode == 0, result.stderr
    assert (
        trace.read_text(encoding="utf-8").strip() == "resolvectl revert tun-securewave"
    )


def test_ikev2_dns_is_split_by_family_with_exclusive_priority(tmp_path: Path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    trace = tmp_path / "trace"
    _write_fake(
        fake_bin / "nmcli",
        'printf \'nmcli %s\\n\' "$*" >> "$TRACE_FILE"\n',
    )

    result = subprocess.run(  # nosec B603
        [str(HELPER), "ikev2-set-dns", "4:1.1.1.1", "6:2606:4700:4700::1111"],
        check=False,
        capture_output=True,
        text=True,
        env=_environment(fake_bin, trace),
    )

    assert result.returncode == 0, result.stderr
    calls = trace.read_text(encoding="utf-8")
    assert "ipv4.ignore-auto-dns yes" in calls
    assert "ipv6.ignore-auto-dns yes" in calls
    assert "+ipv4.dns 1.1.1.1" in calls
    assert "+ipv6.dns 2606:4700:4700::1111" in calls
    assert "ipv4.dns-priority -50 +ipv4.dns-search ~." in calls
    assert "ipv6.dns-priority -50 +ipv6.dns-search ~." in calls


def test_ikev2_dns_does_not_set_priority_for_absent_family(tmp_path: Path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    trace = tmp_path / "trace"
    _write_fake(
        fake_bin / "nmcli",
        'printf \'nmcli %s\\n\' "$*" >> "$TRACE_FILE"\n',
    )

    result = subprocess.run(  # nosec B603
        [str(HELPER), "ikev2-set-dns", "4:1.1.1.1"],
        check=False,
        capture_output=True,
        text=True,
        env=_environment(fake_bin, trace),
    )

    assert result.returncode == 0, result.stderr
    calls = trace.read_text(encoding="utf-8")
    assert "ipv4.dns-priority -50" in calls
    assert "ipv6.dns-priority" not in calls
