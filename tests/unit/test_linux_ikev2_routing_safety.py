import os
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "securewave_app/packaging/linux/securewave-wg-quick"


pytestmark = pytest.mark.skip(
    reason="IKEv2 routing safety is deferred from the Linux WireGuard beta"
)


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
  [[ "${1:-}" == "-N" ]] && shift
  if [[ "${1:-} ${2:-}" == "rule show" ]]; then
    cat "$state"
    exit 0
  fi
  if [[ "${1:-} ${2:-}" == "rule del" ]]; then
    shift 2
    [[ "$*" == "pref 210 from all table 210" ]] || exit 64
    awk '$0 !~ /^210:[[:space:]]+from all lookup 210$/' "$state" > "$state.tmp"
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
    ip6tables_save = fake_bin / "ip6tables-save"
    ip6tables_save.write_text(
        "#!/usr/bin/env bash\nprintf '*filter\\nCOMMIT\\n'\n",
        encoding="utf-8",
    )
    ip6tables_save.chmod(0o755)
    ip6tables_restore = fake_bin / "ip6tables-restore"
    ip6tables_restore.write_text(
        "#!/usr/bin/env bash\ncat >/dev/null\n",
        encoding="utf-8",
    )
    ip6tables_restore.chmod(0o755)
    ip6tables = fake_bin / "ip6tables"
    ip6tables.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    ip6tables.chmod(0o755)
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
        "0: from all lookup local\n210: from all lookup 210\n",
        "0: from all lookup local\n210:\tfrom all lookup 210\n",
    )

    assert result.returncode == 0, result.stderr
    assert "lookup 210" not in rules4
    assert "lookup 210" not in rules6
    assert "-4 rule del pref 210 from all table 210" in log
    assert "-6 rule del pref 210 from all table 210" in log


def test_helper_preserves_safe_and_foreign_charon_nm_rules(tmp_path):
    safe4 = "210: from all not fwmark 0xdc lookup 210\n"
    selector6 = "210: from 192.0.2.0/24 lookup 210\n"
    result, rules4, rules6, log = _run_helper(tmp_path, safe4, selector6)

    assert result.returncode == 0, result.stderr
    assert rules4 == safe4
    assert rules6 == selector6
    assert "rule del" not in log


def test_helper_does_not_modify_system_charon_table_220(tmp_path):
    system_rule = "220: from all lookup 220\n"
    result, rules4, rules6, log = _run_helper(
        tmp_path,
        system_rule,
        system_rule,
    )

    assert result.returncode == 0, result.stderr
    assert rules4 == system_rule
    assert rules6 == system_rule
    assert "rule del" not in log


def test_helper_fails_closed_on_mixed_unsafe_and_foreign_rules(tmp_path):
    mixed = "210: from all not fwmark 0xdc lookup 210\n210: from all lookup 210\n"
    result, rules4, _, log = _run_helper(tmp_path, mixed, "")

    assert result.returncode != 0
    assert "refusing to alter mixed -4 charon-nm policy rules" in result.stderr
    assert rules4 == mixed
    assert "rule del" not in log


def test_ikev2_add_eap_rejects_non_allowlisted_profile_values():
    invalid_args = (
        ("vpn.example.test", "swikev2-" + "a" * 32, "A" * 32),
        ("192.0.2.10", "testuser@example.com", "A" * 32),
        ("192.0.2.10", "swikev2-" + "a" * 32, "unsafe secret"),
        (
            "192.0.2.10",
            "swikev2-" + "a" * 32,
            "A" * 32,
            "vpn.example.test,method=eap",
        ),
    )
    for args in invalid_args:
        result = subprocess.run(
            [str(HELPER), "ikev2-add-eap", *args],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert result.returncode == 64
        assert "refusing" in result.stderr


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
if [[ "$*" == "-t -f NAME,TYPE connection show --active" ]]; then
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


IKEV2_BLOCK_SAVE_LINE = (
    '-A OUTPUT -d 2000::/3 -m mark ! --mark 0xdc/0xffffffff '
    '-m comment --comment "securewave-ikev2-ipv6-block-v1" '
    '-j REJECT --reject-with icmp6-adm-prohibited'
)


def _install_ikev2_lifecycle_fakes(tmp_path: Path) -> tuple[Path, dict[str, Path]]:
    tmp_path.mkdir(parents=True, exist_ok=True)
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    paths = {
        "events": tmp_path / "events.log",
        "firewall": tmp_path / "firewall.rules",
        "active": tmp_path / "active.connections",
        "profiles": tmp_path / "profiles.connections",
        "rules4": tmp_path / "rules4",
        "rules6": tmp_path / "rules6",
    }
    for path in paths.values():
        path.write_text("", encoding="utf-8")

    ip = fake_bin / "ip"
    ip.write_text(
        """#!/usr/bin/env bash
printf 'ip %s\\n' "$*" >> "$SECUREWAVE_TEST_EVENTS"
if [[ "${1:-}" == "-4" || "${1:-}" == "-6" ]]; then
  family="$1"
  shift
  [[ "${1:-}" == "-N" ]] && shift
  if [[ "${1:-} ${2:-}" == "rule show" ]]; then
    [[ "$family" == "-4" ]] && cat "$SECUREWAVE_TEST_RULES4" || cat "$SECUREWAVE_TEST_RULES6"
    exit 0
  fi
  if [[ "${1:-} ${2:-}" == "route flush" ]]; then
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
    nmcli.write_text(
        """#!/usr/bin/env bash
if [[ "$*" == "-t -f NAME,TYPE connection show --active" ]]; then
  cat "$SECUREWAVE_TEST_ACTIVE"
  exit 0
fi
if [[ "$*" == "-t -f NAME,TYPE connection show" ]]; then
  cat "$SECUREWAVE_TEST_PROFILES"
  exit 0
fi
printf 'nmcli %s\\n' "$*" >> "$SECUREWAVE_TEST_EVENTS"
if [[ "$*" == "connection up id SecureWave-IKEv2" ]]; then
  [[ "${SECUREWAVE_TEST_FAIL_UP:-0}" == "1" ]] && exit 7
  printf 'SecureWave-IKEv2:vpn\\n' > "$SECUREWAVE_TEST_ACTIVE"
  exit 0
fi
if [[ "$*" == "connection down id SecureWave-IKEv2" ]]; then
  [[ "${SECUREWAVE_TEST_FAIL_DOWN:-0}" == "1" ]] && exit 8
  : > "$SECUREWAVE_TEST_ACTIVE"
  exit 0
fi
if [[ "$*" == "connection delete id SecureWave-IKEv2" ]]; then
  [[ "${SECUREWAVE_TEST_FAIL_DELETE:-0}" == "1" ]] && exit 9
  : > "$SECUREWAVE_TEST_PROFILES"
  : > "$SECUREWAVE_TEST_ACTIVE"
  exit 0
fi
exit 64
""",
        encoding="utf-8",
    )
    nmcli.chmod(0o755)

    ip6tables_save = fake_bin / "ip6tables-save"
    ip6tables_save.write_text(
        """#!/usr/bin/env bash
printf '*filter\\n'
cat "$SECUREWAVE_TEST_FIREWALL"
printf 'COMMIT\\n'
""",
        encoding="utf-8",
    )
    ip6tables_save.chmod(0o755)

    ip6tables = fake_bin / "ip6tables"
    ip6tables.write_text(
        f"""#!/usr/bin/env bash
printf 'ip6tables %s\\n' "$*" >> "$SECUREWAVE_TEST_EVENTS"
expected='-I OUTPUT 1 -d 2000::/3 -m mark ! --mark 0xdc/0xffffffff -m comment --comment securewave-ikev2-ipv6-block-v1 -j REJECT --reject-with icmp6-adm-prohibited'
[[ "$*" == "$expected" ]] || exit 64
printf '%s\\n' '{IKEV2_BLOCK_SAVE_LINE}' > "$SECUREWAVE_TEST_FIREWALL"
""",
        encoding="utf-8",
    )
    ip6tables.chmod(0o755)

    ip6tables_restore = fake_bin / "ip6tables-restore"
    ip6tables_restore.write_text(
        """#!/usr/bin/env bash
printf 'ip6tables-restore %s\\n' "$*" >> "$SECUREWAVE_TEST_EVENTS"
removed=0
while IFS= read -r line; do
  if [[ "$line" == "-D OUTPUT "* &&
        "$line" == *'--comment "securewave-ikev2-ipv6-block-v1"'* ]]; then
    removed=1
  fi
done
[[ "$removed" == "1" ]] && : > "$SECUREWAVE_TEST_FIREWALL"
""",
        encoding="utf-8",
    )
    ip6tables_restore.chmod(0o755)
    return fake_bin, paths


def _run_ikev2_lifecycle(
    tmp_path: Path,
    action: str,
    *,
    block_present: bool = False,
    active: bool = False,
    profile: bool = True,
    fail_up: bool = False,
    fail_down: bool = False,
    fail_delete: bool = False,
    legacy_loop: bool = False,
) -> tuple[subprocess.CompletedProcess[str], dict[str, Path]]:
    fake_bin, paths = _install_ikev2_lifecycle_fakes(tmp_path)
    if block_present:
        paths["firewall"].write_text(IKEV2_BLOCK_SAVE_LINE + "\n", encoding="utf-8")
    if active:
        paths["active"].write_text("SecureWave-IKEv2:vpn\n", encoding="utf-8")
    if profile:
        paths["profiles"].write_text("SecureWave-IKEv2:vpn\n", encoding="utf-8")
    if legacy_loop:
        legacy = "220: from all lookup 220\n"
        paths["rules4"].write_text(legacy, encoding="utf-8")
        paths["rules6"].write_text(legacy, encoding="utf-8")
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fake_bin}:/usr/bin:/bin",
            "SECUREWAVE_TEST_EVENTS": str(paths["events"]),
            "SECUREWAVE_TEST_FIREWALL": str(paths["firewall"]),
            "SECUREWAVE_TEST_ACTIVE": str(paths["active"]),
            "SECUREWAVE_TEST_PROFILES": str(paths["profiles"]),
            "SECUREWAVE_TEST_RULES4": str(paths["rules4"]),
            "SECUREWAVE_TEST_RULES6": str(paths["rules6"]),
            "SECUREWAVE_TEST_FAIL_UP": "1" if fail_up else "0",
            "SECUREWAVE_TEST_FAIL_DOWN": "1" if fail_down else "0",
            "SECUREWAVE_TEST_FAIL_DELETE": "1" if fail_delete else "0",
        }
    )
    result = subprocess.run(
        [str(HELPER), action],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )
    return result, paths


def test_ikev2_up_installs_block_before_nmcli_and_rolls_back_failed_up(tmp_path):
    result, paths = _run_ikev2_lifecycle(tmp_path, "ikev2-up", fail_up=True)

    assert result.returncode == 7, result.stderr
    assert paths["firewall"].read_text(encoding="utf-8") == ""
    events = paths["events"].read_text(encoding="utf-8")
    assert events.index("ip6tables -I OUTPUT 1") < events.index(
        "nmcli connection up id SecureWave-IKEv2"
    )
    assert "ip6tables-restore -n" in events


def test_ikev2_up_refuses_legacy_pref_220_loop_without_modifying_it(tmp_path):
    result, paths = _run_ikev2_lifecycle(
        tmp_path,
        "ikev2-up",
        legacy_loop=True,
    )

    assert result.returncode != 0
    assert "unqualified pref-220 lookup-220 routing" in result.stderr
    assert paths["rules4"].read_text(encoding="utf-8") == "220: from all lookup 220\n"
    assert paths["rules6"].read_text(encoding="utf-8") == "220: from all lookup 220\n"
    events = paths["events"].read_text(encoding="utf-8")
    assert "nmcli connection up" not in events
    assert "ip6tables -I OUTPUT" not in events


def test_ikev2_down_keeps_block_until_deactivation_is_confirmed(tmp_path):
    failed, failed_paths = _run_ikev2_lifecycle(
        tmp_path / "failed",
        "ikev2-down",
        block_present=True,
        active=True,
        fail_down=True,
    )
    assert failed.returncode != 0
    assert failed_paths["firewall"].read_text(encoding="utf-8") == (
        IKEV2_BLOCK_SAVE_LINE + "\n"
    )

    stopped, stopped_paths = _run_ikev2_lifecycle(
        tmp_path / "stopped",
        "ikev2-down",
        block_present=True,
        active=True,
    )
    assert stopped.returncode == 0, stopped.stderr
    assert stopped_paths["active"].read_text(encoding="utf-8") == ""
    assert stopped_paths["firewall"].read_text(encoding="utf-8") == ""


def test_ikev2_delete_keeps_block_on_failure_and_clears_after_success(tmp_path):
    failed, failed_paths = _run_ikev2_lifecycle(
        tmp_path / "failed",
        "ikev2-delete",
        block_present=True,
        active=True,
        fail_delete=True,
    )
    assert failed.returncode != 0
    assert failed_paths["firewall"].read_text(encoding="utf-8") == (
        IKEV2_BLOCK_SAVE_LINE + "\n"
    )

    deleted, deleted_paths = _run_ikev2_lifecycle(
        tmp_path / "deleted",
        "ikev2-delete",
        block_present=True,
        active=True,
    )
    assert deleted.returncode == 0, deleted.stderr
    assert deleted_paths["profiles"].read_text(encoding="utf-8") == ""
    assert deleted_paths["active"].read_text(encoding="utf-8") == ""
    assert deleted_paths["firewall"].read_text(encoding="utf-8") == ""
