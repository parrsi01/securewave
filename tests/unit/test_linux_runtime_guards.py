from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick"
HELPERD = ROOT / "securewave_app" / "linux" / "helperd" / "securewave_helperd.cc"
CONTRACT = ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick.contract"
SERVICE = ROOT / "securewave_app" / "packaging" / "linux" / "securewave-helper.service"
TMPFILES = ROOT / "securewave_app" / "packaging" / "linux" / "securewave-helper.tmpfiles"
INSTALLER = ROOT / "securewave_app" / "scripts" / "install_linux_helper.sh"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_helper_contract_version_matches_daemon():
    helperd = _read(HELPERD)
    contract = _read(CONTRACT).strip()

    assert contract == "11"
    assert "const guint kContractVersion = 11;" in helperd
    assert 'kContractPath = "/usr/local/libexec/securewave-wg-quick.contract"' in helperd


def test_helper_daemon_uses_securewave_group_socket_and_allowed_uid_file():
    helperd = _read(HELPERD)

    assert 'kSocketPath = "/run/securewave/helper.sock"' in helperd
    assert 'kRuntimeDir = "/run/securewave"' in helperd
    assert 'kAllowedUsersPath = "/etc/securewave/helper-users"' in helperd
    assert 'kGroupName = "securewave"' in helperd
    assert "SO_PEERCRED" in helperd
    assert "UidAllowedByFile" in helperd
    assert 'Error("unauthorized"' in helperd


def test_helper_daemon_inspects_legacy_adblock_chain_without_user_input():
    helperd = _read(HELPERD)

    assert 'kAdblockChainName = "SECUREWAVE_ADBLOCK"' in helperd
    assert 'RunCommand({"iptables", "-S", kAdblockChainName})' in helperd
    assert 'op == "firewall.adblock_status"' in helperd
    assert 'RequestFieldsAllowed(request, {"version", "op"})' in helperd
    assert '"inspection_failed"' in helperd


def test_privileged_helper_script_restricts_inputs_and_protocol_actions():
    helper = _read(HELPER)

    assert "require_safe_config_path" in helper
    assert "require_safe_runtime_file" in helper
    assert "require_sw_wg_iface" in helper
    assert 'if [[ "$iface" != "sw-wg" ]]' in helper
    assert "wireguard-transfer" in helper
    assert "xfrm-state" in helper
    assert "openvpn-start <config-path> <pid-path> <log-path> [auth-path]" in helper
    assert "ikev2-add-eap <server> <username> <password> [remote-id] [ca-cert-path]" in helper
    assert "cert-source=file" in helper


def test_systemd_and_tmpfiles_define_no_prompt_helper_socket_model():
    service = _read(SERVICE)
    tmpfiles = _read(TMPFILES)

    assert "ExecStart=/usr/local/libexec/securewave-helperd" in service
    assert "User=root" in service
    assert "Group=securewave" in service
    assert "RuntimeDirectory=securewave" in service
    assert "RuntimeDirectoryMode=0750" in service
    assert "NoNewPrivileges=yes" in service
    assert "UMask=0077" in service
    assert "LockPersonality=yes" in service
    assert "RestrictSUIDSGID=yes" in service
    assert tmpfiles.strip() == "d /run/securewave 0750 root securewave -"


def test_install_helper_script_installs_payload_and_removes_old_polkit_rule():
    installer = _read(INSTALLER)

    assert 'HELPER_DIR="/usr/local/libexec"' in installer
    assert 'SERVICE_FILE="/etc/systemd/system/securewave-helper.service"' in installer
    assert 'TMPFILES_FILE="/usr/lib/tmpfiles.d/securewave-helper.conf"' in installer
    assert 'AUTH_FILE="$AUTH_DIR/helper-users"' in installer
    assert 'OLD_POLKIT_RULE="/etc/polkit-1/rules.d/50-securewave-wg.rules"' in installer
    assert 'groupadd --system "$RUNTIME_GROUP"' in installer
    assert 'usermod -a -G "$RUNTIME_GROUP" "$user"' in installer
    assert "done < /etc/passwd" not in installer
    assert 'rm -f "$OLD_POLKIT_RULE"' in installer
    assert "systemctl daemon-reload" in installer
    assert "systemctl enable --now securewave-helper.service" in installer
