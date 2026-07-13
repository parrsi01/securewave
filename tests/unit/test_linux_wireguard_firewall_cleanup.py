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


def _install_firewall_fakes(fake_bin: Path) -> None:
    _write_fake(
        fake_bin / "nft",
        """if [[ "$*" == "list tables" ]]; then
  printf 'table ip wg-quick-sw-wg\n'
  printf 'table ip6 foreign-table\n'
  exit 0
fi
printf 'nft %s\n' "$*" >> "$TRACE_FILE"
""",
    )
    save_output = """printf '*raw\n'
printf '%s\n' '-A PREROUTING -m comment --comment "wg-quick(8) rule for sw-wg" -j DROP'
printf '%s\n' '-A PREROUTING -m comment --comment "foreign rule" -j ACCEPT'
printf 'COMMIT\n'
"""
    _write_fake(fake_bin / "iptables-save", save_output)
    _write_fake(fake_bin / "ip6tables-save", save_output)
    restore = """printf '%s\n' "$0 $*" >> "$TRACE_FILE"
while IFS= read -r line; do
  printf 'restore %s\n' "$line" >> "$TRACE_FILE"
done
"""
    _write_fake(fake_bin / "iptables-restore", restore)
    _write_fake(fake_bin / "ip6tables-restore", restore)
    _write_fake(fake_bin / "iptables", "exit 1\n")
    _write_fake(fake_bin / "ip6tables", "exit 1\n")
    _write_fake(
        fake_bin / "ip",
        """printf 'ip %s\n' "$*" >> "$TRACE_FILE"
if [[ "${1:-}" == "rule" && "${2:-}" == "del" ]]; then exit 1; fi
exit 0
""",
    )


def test_policy_clear_removes_only_exact_owned_wg_quick_firewall(
    tmp_path: Path,
):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    trace = tmp_path / "trace"
    _install_firewall_fakes(fake_bin)

    result = subprocess.run(  # nosec B603
        [str(HELPER), "policy-clear-link", "sw-wg"],
        check=False,
        capture_output=True,
        text=True,
        env=_environment(fake_bin, trace),
    )

    assert result.returncode == 0, result.stderr
    calls = trace.read_text(encoding="utf-8")
    assert "nft delete table ip wg-quick-sw-wg" in calls
    assert "foreign-table" not in calls
    assert '-D PREROUTING -m comment --comment "wg-quick(8) rule for sw-wg"' in calls
    assert "foreign rule" not in calls
    assert "ip link delete sw-wg" in calls


def test_active_policy_reconciliation_does_not_touch_firewall(
    tmp_path: Path,
):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    trace = tmp_path / "trace"
    _write_fake(fake_bin / "wg", 'printf \'wg %s\\n\' "$*" >> "$TRACE_FILE"\n')
    _write_fake(
        fake_bin / "ip",
        """printf 'ip %s\n' "$*" >> "$TRACE_FILE"
if [[ "$*" == "rule show" ]]; then
  printf '100: from all not fwmark 51820 lookup 51820\n'
  printf '101: from all not fwmark 51820 lookup 51820\n'
  printf '102: from all lookup main suppress_prefixlength 0\n'
  printf '103: from all lookup main suppress_prefixlength 0\n'
elif [[ "$*" == "-4 route show table 51820" ]]; then
  printf 'default dev sw-wg\n'
elif [[ "${1:-}" == "rule" && "${2:-}" == "del" ]]; then
  exit 1
fi
exit 0
""",
    )
    for command in (
        "nft",
        "iptables",
        "ip6tables",
        "iptables-save",
        "ip6tables-save",
        "iptables-restore",
        "ip6tables-restore",
    ):
        _write_fake(
            fake_bin / command,
            f"printf 'unexpected {command}\\n' >> \"$TRACE_FILE\"\nexit 99\n",
        )

    result = subprocess.run(  # nosec B603
        [str(HELPER), "policy-ensure", "sw-wg"],
        check=False,
        capture_output=True,
        text=True,
        env=_environment(fake_bin, trace),
    )

    assert result.returncode == 0, result.stderr
    calls = trace.read_text(encoding="utf-8")
    assert "unexpected" not in calls
    assert "ip link delete" not in calls
