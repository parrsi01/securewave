from __future__ import annotations

import os
import subprocess  # nosec B404
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "securewave_app/packaging/linux/securewave-wg-quick"


def _write_executable(path: Path, contents: str) -> None:
    path.write_text(contents, encoding="utf-8")
    path.chmod(0o755)


def test_wireguard_policy_ensure_repairs_both_address_families(tmp_path: Path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    event_log = tmp_path / "events.log"
    state_paths: dict[str, Path] = {}
    for family in ("4", "6"):
        for kind in ("rules", "routes"):
            path = tmp_path / f"{kind}{family}"
            path.write_text("", encoding="utf-8")
            state_paths[f"{kind}{family}"] = path

    _write_executable(
        fake_bin / "wg",
        """#!/usr/bin/env bash
printf 'wg %s\n' "$*" >> "$SECUREWAVE_TEST_EVENTS"
""",
    )
    _write_executable(
        fake_bin / "ip",
        """#!/usr/bin/env bash
printf 'ip %s\n' "$*" >> "$SECUREWAVE_TEST_EVENTS"
family="${1#-}"
[[ "$family" == "4" || "$family" == "6" ]] || exit 64
shift
[[ "${1:-}" == "-N" ]] && shift
rules_var="SECUREWAVE_TEST_RULES${family}"
routes_var="SECUREWAVE_TEST_ROUTES${family}"
rules="${!rules_var}"
routes="${!routes_var}"
if [[ "${1:-} ${2:-}" == "rule show" ]]; then
  cat "$rules"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "route show" ]]; then
  cat "$routes"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "route replace" ]]; then
  printf 'default dev sw-wg\n' > "$routes"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "route flush" ]]; then
  if [[ "${3:-}" == "table" ]]; then
    : > "$routes"
  fi
  exit 0
fi
if [[ "${1:-} ${2:-}" == "rule add" ]]; then
  shift 2
  if [[ "$*" == "not fwmark 51820 table 51820 priority 32764" ]]; then
    printf '32764: not from all fwmark 0xca6c lookup 51820\n' >> "$rules"
    exit 0
  fi
  if [[ "$*" == "table main suppress_prefixlength 0 priority 32765" ]]; then
    printf '32765: from all lookup main suppress_prefixlength 0\n' >> "$rules"
    exit 0
  fi
fi
if [[ "${1:-} ${2:-}" == "rule del" ]]; then
  exit 1
fi
exit 64
""",
    )
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fake_bin}:/usr/bin:/bin",
            "SECUREWAVE_TEST_EVENTS": str(event_log),
            "SECUREWAVE_TEST_RULES4": str(state_paths["rules4"]),
            "SECUREWAVE_TEST_RULES6": str(state_paths["rules6"]),
            "SECUREWAVE_TEST_ROUTES4": str(state_paths["routes4"]),
            "SECUREWAVE_TEST_ROUTES6": str(state_paths["routes6"]),
        }
    )

    initial = subprocess.run(  # nosec B603
        [str(WRAPPER), "policy-ensure", "sw-wg"],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )
    assert initial.returncode == 0, initial.stderr
    for family in ("4", "6"):
        assert state_paths[f"routes{family}"].read_text(encoding="utf-8") == (
            "default dev sw-wg\n"
        )
        rules = state_paths[f"rules{family}"].read_text(encoding="utf-8")
        assert "32764: not from all fwmark 0xca6c lookup 51820" in rules
        assert "32765: from all lookup main suppress_prefixlength 0" in rules

    # wg-quick normally lets the kernel allocate these two priorities in the
    # opposite order from the wrapper's deterministic repair priorities. Both
    # shapes are owned and must be preserved instead of duplicated.
    state_paths["rules4"].write_text(
        "32765: not from all fwmark 0xca6c lookup 51820\n"
        "32764: from all lookup main suppress_prefixlength 0\n",
        encoding="utf-8",
    )
    state_paths["routes6"].write_text("", encoding="utf-8")
    state_paths["rules6"].write_text("", encoding="utf-8")
    event_log.write_text("", encoding="utf-8")
    repaired = subprocess.run(  # nosec B603
        [str(WRAPPER), "policy-ensure", "sw-wg"],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )
    assert repaired.returncode == 0, repaired.stderr
    events = event_log.read_text(encoding="utf-8")
    assert "ip -6 route replace default dev sw-wg table 51820" in events
    assert "ip -6 rule add not fwmark 51820 table 51820 priority 32764" in events
    assert "ip -6 rule add table main suppress_prefixlength 0 priority 32765" in events
    assert "ip -4 route replace" not in events
    assert "ip -4 rule add" not in events


def test_wireguard_cleanup_removes_versioned_and_legacy_owned_rules(tmp_path: Path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    events = tmp_path / "events.log"
    v4_versioned = tmp_path / "v4-versioned"
    v6_versioned = tmp_path / "v6-versioned"
    v4_legacy = tmp_path / "v4-legacy"
    v6_legacy = tmp_path / "v6-legacy"
    v4_versioned.write_text(
        '-A OUTPUT ! -o sw-wg -m mark ! --mark 0xca6c '
        '-m addrtype ! --dst-type LOCAL -m comment '
        '--comment "securewave-wireguard-ipv4-kill-switch-v1" -j REJECT\n',
        encoding="utf-8",
    )
    v6_versioned.write_text(
        '-A OUTPUT -d 2000::/3 -m mark ! --mark 0xca6c '
        '-m comment --comment "securewave-wireguard-ipv6-block-v1" '
        '-j REJECT --reject-with icmp6-adm-prohibited\n',
        encoding="utf-8",
    )
    v4_legacy.write_text("present\n", encoding="utf-8")
    v6_legacy.write_text("present\n", encoding="utf-8")

    _write_executable(fake_bin / "nft", "#!/usr/bin/env bash\nexit 0\n")
    for family, tool in (("4", "iptables"), ("6", "ip6tables")):
        _write_executable(
            fake_bin / f"{tool}-save",
            f"""#!/usr/bin/env bash
printf '*filter\\n'
cat "$SECUREWAVE_TEST_V{family}_VERSIONED"
printf 'COMMIT\\n'
""",
        )
        _write_executable(
            fake_bin / f"{tool}-restore",
            f"""#!/usr/bin/env bash
while IFS= read -r line; do
  if [[ "$line" == "-D OUTPUT "* && "$line" == *securewave-wireguard-* ]]; then
    : > "$SECUREWAVE_TEST_V{family}_VERSIONED"
  fi
done
""",
        )
        _write_executable(
            fake_bin / tool,
            f"""#!/usr/bin/env bash
printf '{tool} %s\\n' "$*" >> "$SECUREWAVE_TEST_EVENTS"
if [[ "$*" == "-D OUTPUT ! -o sw-wg -m mark ! --mark 51820 -m addrtype ! --dst-type LOCAL -j REJECT" &&
      -s "$SECUREWAVE_TEST_V{family}_LEGACY" ]]; then
  : > "$SECUREWAVE_TEST_V{family}_LEGACY"
  exit 0
fi
exit 1
""",
        )
    _write_executable(
        fake_bin / "ip",
        """#!/usr/bin/env bash
if [[ "${1:-}" == "-4" || "${1:-}" == "-6" ]]; then
  if [[ "$*" == *"rule show"* || "$*" == *"route show"* ]]; then
    exit 0
  fi
  if [[ "$*" == *"route flush"* ]]; then
    exit 0
  fi
fi
if [[ "${1:-} ${2:-}" == "link delete" ]]; then
  exit 0
fi
exit 64
""",
    )
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fake_bin}:/usr/bin:/bin",
            "SECUREWAVE_TEST_EVENTS": str(events),
            "SECUREWAVE_TEST_V4_VERSIONED": str(v4_versioned),
            "SECUREWAVE_TEST_V6_VERSIONED": str(v6_versioned),
            "SECUREWAVE_TEST_V4_LEGACY": str(v4_legacy),
            "SECUREWAVE_TEST_V6_LEGACY": str(v6_legacy),
        }
    )
    result = subprocess.run(  # nosec B603
        [str(WRAPPER), "policy-clear-link", "sw-wg"],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )

    assert result.returncode == 0, result.stderr
    assert v4_versioned.read_text(encoding="utf-8") == ""
    assert v6_versioned.read_text(encoding="utf-8") == ""
    assert v4_legacy.read_text(encoding="utf-8") == ""
    assert v6_legacy.read_text(encoding="utf-8") == ""
