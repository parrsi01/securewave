import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "securewave_app/packaging/linux/securewave-wg-quick"


def _install_fake_network_tools(tmp_path: Path) -> tuple[Path, Path, Path, Path]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    state4 = tmp_path / "rules4"
    state6 = tmp_path / "rules6"
    log = tmp_path / "ip.log"

    ip = fake_bin / "ip"
    ip.write_text(
        """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$SECUREWAVE_TEST_IP_LOG"
family="${1:-}"
if [[ "$family" == "-4" || "$family" == "-6" ]]; then
  state="$SECUREWAVE_TEST_STATE4"
  [[ "$family" == "-6" ]] && state="$SECUREWAVE_TEST_STATE6"
  shift
  if [[ "${1:-} ${2:-}" == "rule show" ]]; then
    cat "$state"
    exit 0
  fi
  if [[ "${1:-} ${2:-}" == "rule del" ]]; then
    shift 2
    [[ "$*" == "pref 220 from all table 220" ]] || exit 64
    awk '$0 !~ /^220:[[:space:]]+from all lookup 220$/' "$state" > "$state.tmp"
    mv "$state.tmp" "$state"
    exit 0
  fi
fi
if [[ "$*" == "route flush cache" ]]; then
  exit 0
fi
exit 64
""",
        encoding="utf-8",
    )
    ip.chmod(0o755)

    nmcli = fake_bin / "nmcli"
    nmcli.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    nmcli.chmod(0o755)
    return fake_bin, state4, state6, log


def _run_helper(
    tmp_path: Path, rules4: str, rules6: str
) -> tuple[subprocess.CompletedProcess[str], str, str, str]:
    fake_bin, state4, state6, log = _install_fake_network_tools(tmp_path)
    state4.write_text(rules4, encoding="utf-8")
    state6.write_text(rules6, encoding="utf-8")
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fake_bin}:{env['PATH']}",
            "SECUREWAVE_TEST_STATE4": str(state4),
            "SECUREWAVE_TEST_STATE6": str(state6),
            "SECUREWAVE_TEST_IP_LOG": str(log),
        }
    )
    result = subprocess.run(
        [str(HELPER), "ikev2-down"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    return result, state4.read_text(), state6.read_text(), log.read_text()


def test_helper_removes_exact_unsafe_rule_from_both_families(tmp_path):
    result, rules4, rules6, log = _run_helper(
        tmp_path,
        "0: from all lookup local\n220: from all lookup 220\n",
        "0: from all lookup local\n220:\tfrom all lookup 220\n",
    )

    assert result.returncode == 0, result.stderr
    assert "lookup 220" not in rules4
    assert "lookup 220" not in rules6
    assert "-4 rule del pref 220 from all table 220" in log
    assert "-6 rule del pref 220 from all table 220" in log


def test_helper_preserves_safe_and_foreign_pref_220_rules(tmp_path):
    safe4 = "220: from all not fwmark 0xdc lookup 220\n"
    selector6 = "220: from 192.0.2.0/24 lookup 220\n"
    result, rules4, rules6, log = _run_helper(tmp_path, safe4, selector6)

    assert result.returncode == 0, result.stderr
    assert rules4 == safe4
    assert rules6 == selector6
    assert "rule del" not in log


def test_helper_fails_closed_on_mixed_unsafe_and_foreign_rules(tmp_path):
    mixed = "220: from all not fwmark 0xdc lookup 220\n220: from all lookup 220\n"
    result, rules4, _, log = _run_helper(tmp_path, mixed, "")

    assert result.returncode != 0
    assert "refusing to alter mixed -4 pref-220 policy rules" in result.stderr
    assert rules4 == mixed
    assert "rule del" not in log


def _run_ikev2_delete(
    tmp_path: Path,
    *,
    initial_connection: bool,
    keep_after_delete: bool = False,
) -> tuple[subprocess.CompletedProcess[str], str]:
    tmp_path.mkdir(parents=True, exist_ok=True)
    fake_bin, state4, state6, _ = _install_fake_network_tools(tmp_path)
    state4.write_text("", encoding="utf-8")
    state6.write_text("", encoding="utf-8")
    connection_state = tmp_path / "connections"
    connection_state.write_text(
        "SecureWave-IKEv2:vpn\n" if initial_connection else "",
        encoding="utf-8",
    )
    nmcli = fake_bin / "nmcli"
    nmcli.write_text(
        """#!/usr/bin/env bash
if [[ "$*" == "-t -f NAME,TYPE connection show" ]]; then
  cat "$SECUREWAVE_TEST_CONNECTIONS"
  exit 0
fi
if [[ "$*" == "connection delete id SecureWave-IKEv2" ]]; then
  if [[ "${SECUREWAVE_TEST_KEEP_CONNECTION:-0}" != "1" ]]; then
    : > "$SECUREWAVE_TEST_CONNECTIONS"
  fi
  exit 0
fi
exit 64
""",
        encoding="utf-8",
    )
    nmcli.chmod(0o755)
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fake_bin}:{env['PATH']}",
            "SECUREWAVE_TEST_STATE4": str(state4),
            "SECUREWAVE_TEST_STATE6": str(state6),
            "SECUREWAVE_TEST_IP_LOG": str(tmp_path / "ip.log"),
            "SECUREWAVE_TEST_CONNECTIONS": str(connection_state),
            "SECUREWAVE_TEST_KEEP_CONNECTION": "1" if keep_after_delete else "0",
        }
    )
    result = subprocess.run(
        [str(HELPER), "ikev2-delete"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    return result, connection_state.read_text(encoding="utf-8")


def test_ikev2_delete_is_idempotent_and_verifies_exact_connection_absence(tmp_path):
    present, state = _run_ikev2_delete(tmp_path, initial_connection=True)
    assert present.returncode == 0, present.stderr
    assert state == ""

    absent, state = _run_ikev2_delete(tmp_path / "absent", initial_connection=False)
    assert absent.returncode == 0, absent.stderr
    assert state == ""


def test_ikev2_delete_fails_closed_when_exact_connection_remains(tmp_path):
    result, state = _run_ikev2_delete(
        tmp_path,
        initial_connection=True,
        keep_after_delete=True,
    )

    assert result.returncode != 0
    assert "profile remains after deletion" in result.stderr
    assert state == "SecureWave-IKEv2:vpn\n"
