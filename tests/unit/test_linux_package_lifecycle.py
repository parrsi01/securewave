import subprocess
from pathlib import Path

import pytest


BUILD_DEB = Path("securewave_app/scripts/build_deb.sh")


def _maintainer_script(name: str) -> str:
    source = BUILD_DEB.read_text(encoding="utf-8")
    marker = f"cat <<'{name}' >"
    start = source.index(marker)
    body_start = source.index("\n", start) + 1
    body_end = source.index(f"\n{name}\n", body_start)
    return source[body_start:body_end] + "\n"


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


def test_maintainer_scripts_keep_wireguard_rollback_boundaries():
    preinst = _maintainer_script("PREINST")
    postinst = _maintainer_script("POSTINST")
    prerm = _maintainer_script("PRERM")
    postrm = _maintainer_script("POSTRM")

    assert 'case "${1:-}" in\n  install|upgrade)' in preinst
    assert 'case "${1:-}" in\n  configure)' in postinst
    assert "abort-upgrade|abort-remove|abort-deconfigure)" in postinst
    assert 'case "${1:-}" in\n  remove|upgrade|failed-upgrade|deconfigure)' in prerm
    assert 'case "${1:-}" in\n  remove|purge)' in postrm
    assert "helper_request" not in prerm
    assert "openvpn" not in prerm.lower()
    assert "strongswan" not in postrm.lower()

    assert 'ip link show dev sw-wg' in prerm
    assert "SecureWave WireGuard interface is still active" in prerm
    assert "systemctl disable --now securewave-helper.service" in prerm

    before_action_case = postrm.split('case "${1:-}" in', 1)[0]
    assert "rm -f" not in before_action_case
    assert "systemctl disable" not in before_action_case

    removal_branch = postrm.split("  remove|purge)", 1)[1].split("    ;;", 1)[0]
    assert "securewave-helper.service" in removal_branch
    assert "/usr/local/libexec/securewave-helperd" in removal_branch
    assert "/usr/lib/tmpfiles.d/securewave-helper.conf" in removal_branch

    purge_guard = 'if [[ "${1:-}" == purge ]]'
    assert postrm.index(purge_guard) < postrm.index(
        "rm -f /etc/securewave/helper-users"
    )


def test_postinst_installs_and_probes_the_wireguard_helper_contract():
    postinst = _maintainer_script("POSTINST")

    assert "securewave-wg-quick" in postinst
    assert "securewave-helperd" in postinst
    assert "securewave-wg-quick.contract" in postinst
    assert "securewave-helper.service" in postinst
    assert "systemctl enable securewave-helper.service" in postinst
    assert "systemctl restart securewave-helper.service" in postinst
    assert "version=1\\nop=probe" in postinst
    assert "grep -qx 'ok=true'" in postinst
    assert "strongswan" not in postinst.lower()
    assert "openvpn" not in postinst.lower()


def test_helper_allowlist_is_preserved_except_on_explicit_purge():
    postinst = _maintainer_script("POSTINST")
    postrm = _maintainer_script("POSTRM")

    assert ': > "$AUTH_FILE"' not in postinst
    assert 'if [[ -e "$AUTH_FILE" || -L "$AUTH_FILE" ]]; then' in postinst
    assert '[[ -f "$AUTH_FILE" && ! -L "$AUTH_FILE" ]]' in postinst
    assert '"$(stat -c %u "$AUTH_FILE" 2>/dev/null || true)" == "0"' in postinst
    assert 'install -o root -g root -m 0644 /dev/null "$AUTH_FILE"' in postinst

    assert postrm.count("rm -f /etc/securewave/helper-users") == 1
    assert postrm.index('if [[ "${1:-}" == purge ]]') < postrm.index(
        "rm -f /etc/securewave/helper-users"
    )


def test_prerm_refuses_active_wireguard_and_stops_only_owned_service():
    prerm = _maintainer_script("PRERM")

    assert "sw-wg" in prerm
    assert "refusing package removal" in prerm
    assert "systemctl disable --now securewave-helper.service" in prerm
    assert "openvpn" not in prerm.lower()
    assert "ikev2" not in prerm.lower()
    assert "strongswan" not in prerm.lower()
