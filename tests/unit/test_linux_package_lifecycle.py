import os
import subprocess
from pathlib import Path

import pytest


BUILD_DEB = Path("securewave_app/scripts/build_deb.sh")
HELPER_INSTALLER = Path("securewave_app/scripts/install_linux_helper.sh")


def _maintainer_script(name: str) -> str:
    source = BUILD_DEB.read_text(encoding="utf-8")
    marker = f"cat <<'{name}' >"
    start = source.index(marker)
    body_start = source.index("\n", start) + 1
    body_end = source.index(f"\n{name}\n", body_start)
    return source[body_start:body_end] + "\n"


def _function_region(source: str, start: str, end: str) -> str:
    return start + source.split(start, 1)[1].split(end, 1)[0]


@pytest.mark.parametrize("name", ("PREINST", "POSTINST", "PRERM", "POSTRM"))
def test_generated_maintainer_scripts_are_valid_bash(name: str):
    result = subprocess.run(
        ["bash", "-n"],
        input=_maintainer_script(name),
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr


def test_maintainer_script_actions_are_scoped_for_dpkg_rollback():
    preinst = _maintainer_script("PREINST")
    postinst = _maintainer_script("POSTINST")
    prerm = _maintainer_script("PRERM")
    postrm = _maintainer_script("POSTRM")

    assert 'case "${1:-}" in\n  install|upgrade)' in preinst
    assert 'case "${1:-}" in\n  configure)' in postinst
    assert "abort-upgrade|abort-remove|abort-deconfigure)" in postinst
    assert 'case "${1:-}" in\n  remove|upgrade|failed-upgrade|deconfigure)' in prerm
    assert 'case "${1:-}" in\n  remove|purge)' in postrm
    assert 'helper_request openvpn.dns_revert' in prerm
    assert '"$HELPER" openvpn-dns-revert' not in prerm
    assert "upgrade|failed-upgrade|abort-install|abort-upgrade|disappear)" in postrm

    before_action_case = postrm.split('case "${1:-}" in', 1)[0]
    assert "rm -f" not in before_action_case
    assert "systemctl disable" not in before_action_case

    removal_branch = postrm.split("  remove|purge)", 1)[1].split("    ;;", 1)[0]
    assert "securewave-helper.service" in removal_branch
    assert "/usr/local/libexec/securewave-helperd" in removal_branch
    assert "/etc/strongswan.d/securewave-routing.conf" in removal_branch

    purge_guard = 'if [[ "${1:-}" == "purge" ]]'
    assert postrm.index(purge_guard) < postrm.index(
        "rm -f /etc/securewave/helper-users"
    )


def test_install_paths_do_not_inspect_or_modify_strongswan_configuration():
    postinst = _maintainer_script("POSTINST")
    installer = HELPER_INSTALLER.read_text(encoding="utf-8")

    for source in (postinst, installer):
        assert "strongswan_file_has_charon_nm_routing_settings" not in source
        assert "find_strongswan_fwmark_conflict" not in source
        assert "install_strongswan_routing_config" not in source
        assert "/etc/strongswan.d" not in source


def test_allowlist_is_preserved_except_on_explicit_purge():
    postinst = _maintainer_script("POSTINST")
    postrm = _maintainer_script("POSTRM")
    installer = HELPER_INSTALLER.read_text(encoding="utf-8")

    for source in (postinst, installer):
        assert ': > "$AUTH_FILE"' not in source
        assert '[[ ! -f "$AUTH_FILE" || -L "$AUTH_FILE"' in source
        assert 'install -o root -g root -m 0644 /dev/null "$AUTH_FILE"' in source

    assert postrm.count("rm -f /etc/securewave/helper-users") == 1
    assert postrm.index('if [[ "${1:-}" == "purge" ]]') < postrm.index(
        "rm -f /etc/securewave/helper-users"
    )


def test_legacy_charon_cleanup_detection_stays_in_prerm_only():
    assert "charon_nm_running()" not in _maintainer_script("PREINST")
    assert "charon_nm_running()" not in _maintainer_script("POSTINST")
    assert "charon_nm_running()" in _maintainer_script("PRERM")
    assert "charon_nm_running()" not in HELPER_INSTALLER.read_text(encoding="utf-8")


def _write_fake_helperd(path: Path):
    path.write_text(
        "#!/bin/bash\n"
        "cat >/dev/null\n"
        "printf '%s\\n' \"${FAKE_RESPONSE:-contract=13}\"\n"
        "exit \"${FAKE_EXIT:-0}\"\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


@pytest.mark.parametrize(
    ("contract_contents", "response", "expected_success"),
    (
        ("13\n", "ok=true\ncontract=13", True),
        ("13\n", "ok=true\ncontract=14", False),
        ("13\n", "contract=13\ncontract=13", False),
        ("1 3\n", "contract=13", False),
        ("13\n14\n", "contract=13", False),
    ),
)
def test_prerm_requires_one_exact_helper_cleanup_contract(
    tmp_path: Path,
    contract_contents: str,
    response: str,
    expected_success: bool,
):
    prerm = _maintainer_script("PRERM")
    helpers = _function_region(prerm, "response_field() {", "charon_nm_running() {")
    helperd = tmp_path / "securewave-helperd"
    contract = tmp_path / "securewave-wg-quick.contract"
    _write_fake_helperd(helperd)
    contract.write_text(contract_contents, encoding="utf-8")
    script = (
        "set -euo pipefail\n"
        'HELPERD="$1"\n'
        'HELPER_CONTRACT="$2"\n'
        + helpers
        + "\nhelper_request wireguard.cleanup\n"
    )
    env = os.environ.copy()
    env["FAKE_RESPONSE"] = response
    result = subprocess.run(
        ["bash", "-c", script, "_", str(helperd), str(contract)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert (result.returncode == 0) is expected_success, result.stderr


def _write_fake_runtime_commands(bin_dir: Path):
    commands = {
        "ip": """#!/bin/bash
if [[ "${FAKE_MODE:-clean}" == "unsafe_route" && "$*" == *"route show table all"* ]]; then
  printf '%s\n' 'default dev eth0 table 210'
elif [[ "${FAKE_MODE:-clean}" == "wireguard_table_route" && "$*" == *"route show table all"* ]]; then
  printf '%s\n' 'default dev eth0 table 51820'
elif [[ "${FAKE_MODE:-clean}" == "unsafe_rule" && "$*" == *"rule show"* ]]; then
  printf '%s\n' '210: from all lookup 210'
elif [[ "${FAKE_MODE:-clean}" == "owned_wireguard_rule" && "$*" == *"rule show"* ]]; then
  printf '%s\n' '32764: not from all fwmark 0xca6c lookup 51820'
  printf '%s\n' '32765: from all lookup main suppress_prefixlength 0'
elif [[ "${FAKE_MODE:-clean}" == "unknown_priority_rules" && "$*" == *"rule show"* ]]; then
  printf '%s\n' '218: from all lookup main suppress_prefixlength 0'
  printf '%s\n' '219: not from all fwmark 0xca6c lookup 51820'
elif [[ "${FAKE_MODE:-clean}" == "legacy_pref220" && "$*" == *"rule show"* ]]; then
  printf '%s\n' '220: from all lookup 220'
elif [[ "${FAKE_MODE:-clean}" == "asymmetric_safe_rule" && "$1" == "-4" && "$*" == *"rule show"* ]]; then
  printf '%s\n' '210: not from all fwmark 0xdc lookup 210'
elif [[ "${FAKE_MODE:-clean}" == "paired_safe_rule" && "$*" == *"rule show"* ]]; then
  printf '%s\n' '210: not from all fwmark 0xdc lookup 210'
elif [[ "${FAKE_MODE:-clean}" == "unsafe_xfrm" && "$*" == *"xfrm state"* ]]; then
  printf '%s\n' 'if_id 0x2a'
elif [[ "${FAKE_MODE:-clean}" == "unsafe_xfrm_policy" && "$*" == *"xfrm policy"* ]]; then
  printf '%s\n' 'if_id 0x2a'
fi
""",
        "nmcli": "#!/bin/bash\nexit 0\n",
        "nft": "#!/bin/bash\nexit 0\n",
        "iptables-save": """#!/bin/bash
[[ "${FAKE_MODE:-clean}" != "iptables_failure" ]] || exit 1
[[ "${FAKE_MODE:-clean}" != "adblock" ]] || printf '%s\n' ':SECUREWAVE_ADBLOCK - [0:0]'
[[ "${FAKE_MODE:-clean}" != "wireguard_firewall" ]] || printf '%s\n' '-A OUTPUT -m comment --comment "wg-quick(8) rule for sw-wg" -j REJECT'
[[ "${FAKE_MODE:-clean}" != "wireguard_ipv4_firewall" ]] || printf '%s\n' '-A OUTPUT -m comment --comment "securewave-wireguard-ipv4-kill-switch-v1" -j REJECT'
""",
        "ip6tables-save": """#!/bin/bash
[[ "${FAKE_MODE:-clean}" != "wireguard_ipv6_firewall" ]] || printf '%s\\n' '-A OUTPUT -m comment --comment "securewave-wireguard-ipv6-block-v1" -j REJECT'
[[ "${FAKE_MODE:-clean}" != "ikev2_firewall" ]] || printf '%s\\n' '-A OUTPUT -m comment --comment "securewave-ikev2-ipv6-block-v1" -j REJECT'
""",
    }
    for name, contents in commands.items():
        command = bin_dir / name
        command.write_text(contents, encoding="utf-8")
        command.chmod(0o755)


@pytest.mark.parametrize(
    ("mode", "expected_success"),
    (
        ("clean", True),
        ("paired_safe_rule", True),
        ("unknown_priority_rules", True),
        ("unsafe_route", False),
        ("wireguard_table_route", False),
        ("unsafe_rule", False),
        ("owned_wireguard_rule", False),
        ("legacy_pref220", False),
        ("adblock", False),
        ("asymmetric_safe_rule", False),
        ("iptables_failure", False),
        ("wireguard_firewall", False),
        ("wireguard_ipv4_firewall", False),
        ("wireguard_ipv6_firewall", False),
        ("unsafe_xfrm", False),
        ("unsafe_xfrm_policy", False),
        ("ikev2_firewall", False),
    ),
)
def test_prerm_offline_cleanup_inspection_fails_closed(
    tmp_path: Path, mode: str, expected_success: bool
):
    prerm = _maintainer_script("PRERM")
    functions = _function_region(
        prerm, "securewave_openvpn_pids() {", "helper_service_active=0"
    )
    runtime_dir = tmp_path / "runtime"
    bin_dir = tmp_path / "bin"
    runtime_dir.mkdir()
    bin_dir.mkdir()
    _write_fake_runtime_commands(bin_dir)
    functions = functions.replace("/run/securewave", str(runtime_dir))
    script = functions + "\nsecurewave_openvpn_pids() { return 0; }\noffline_owned_runtime_clean\n"
    env = os.environ.copy()
    env["FAKE_MODE"] = mode
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    result = subprocess.run(
        ["bash", "-c", script],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert (result.returncode == 0) is expected_success, result.stderr


def test_prerm_falls_back_to_clean_offline_inspection_for_legacy_ikev2_helper(
    tmp_path: Path,
):
    prerm = _maintainer_script("PRERM")
    helper_functions = _function_region(
        prerm, "response_field() {", "charon_nm_running() {"
    )
    offline_functions = _function_region(
        prerm, "securewave_openvpn_pids() {", "helper_service_active=0"
    )
    helperd = tmp_path / "securewave-helperd"
    contract = tmp_path / "securewave-wg-quick.contract"
    runtime_dir = tmp_path / "runtime"
    bin_dir = tmp_path / "bin"
    runtime_dir.mkdir()
    bin_dir.mkdir()
    _write_fake_helperd(helperd)
    contract.write_text("13\n", encoding="utf-8")
    _write_fake_runtime_commands(bin_dir)
    script = (
        "set -euo pipefail\n"
        'HELPERD="$1"\n'
        'HELPER_CONTRACT="$2"\n'
        + helper_functions
        + offline_functions.replace("/run/securewave", str(runtime_dir))
        + "\n"
        + "if ! helper_request ikev2.cleanup; then\n"
        + "  offline_owned_runtime_clean\n"
        + "fi\n"
    )
    env = os.environ.copy()
    env["FAKE_RESPONSE"] = "ok=false\ncontract=13\nmessage=inspection_failed"
    env["FAKE_EXIT"] = "1"
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    result = subprocess.run(
        ["bash", "-c", script, "_", str(helperd), str(contract)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr


def test_prerm_half_configured_removal_and_service_retry_are_idempotent():
    prerm = _maintainer_script("PRERM")

    assert "offline_owned_runtime_clean()" in prerm
    assert 'elif [[ -x "$HELPER" && -x "$HELPERD" ]]' in prerm
    assert "systemctl start securewave-helper.service" in prerm
    assert 'if [[ "$helper_service_active" == "1" && -x "$HELPERD" ]]; then\n  if ! helper_request openvpn.dns_revert; then' in prerm
    assert "elif ! offline_owned_runtime_clean; then" in prerm
    assert "if ! systemctl stop securewave-helper.service; then" in prerm
    assert "systemctl is-active --quiet securewave-helper.service" in prerm
    assert "systemctl disable securewave-helper.service >/dev/null 2>&1 || true" in prerm


def test_prerm_keeps_pref220_as_a_hard_blocker_and_has_no_force_path():
    prerm = _maintainer_script("PRERM")

    assert "pref220_ikev2_rule_present()" in prerm
    assert "Unowned pref-220/table-220 IKEv2 routing state remains" in prerm
    assert "if ! helper_request wireguard.cleanup; then" in prerm
    assert '"$HELPER" openvpn-stop "$pid"' in prerm
    assert "kill -TERM" not in prerm
    assert "dpkg --force" not in prerm
    assert "--force-" not in prerm


def test_standalone_installer_runs_read_only_gates_before_mutation():
    installer = HELPER_INSTALLER.read_text(encoding="utf-8")
    calls = installer.rsplit("install_systemd_service()", 1)[1]

    first_preflight = calls.index("preflight_install")
    dependency_install = calls.index("install_apt_dependencies")
    group_mutation = calls.index("ensure_runtime_group")

    assert first_preflight < dependency_install < group_mutation
    assert "command -v systemctl" in installer.split("preflight_install() {", 1)[1]
    assert "[[ -d /run/systemd/system ]]" in installer.split(
        "preflight_install() {", 1
    )[1]
