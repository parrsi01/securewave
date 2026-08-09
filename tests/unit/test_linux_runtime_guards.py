from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick"
HELPERD = ROOT / "securewave_app" / "linux" / "helperd" / "securewave_helperd.cc"
CONTRACT = (
    ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick.contract"
)
SERVICE = ROOT / "securewave_app" / "packaging" / "linux" / "securewave-helper.service"
TMPFILES = (
    ROOT / "securewave_app" / "packaging" / "linux" / "securewave-helper.tmpfiles"
)
INSTALLER = ROOT / "securewave_app" / "scripts" / "install_linux_helper.sh"
STRONGSWAN_ROUTING = (
    ROOT
    / "securewave_app"
    / "packaging"
    / "linux"
    / "securewave-strongswan-routing.conf"
)
RUNNER = ROOT / "securewave_app" / "linux" / "runner" / "my_application.cc"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_linux_runner_accepts_only_wireguard_protocol_contracts():
    runner = _read(RUNNER)

    assert 'return g_strcmp0(protocol, "wireguard") == 0;' in runner
    assert 'return "wireguard.up";' in runner
    assert 'return "wireguard.down";' in runner


def test_helper_contract_version_matches_daemon():
    helperd = _read(HELPERD)
    contract = _read(CONTRACT).strip()

    assert contract == "13"
    assert "const guint kContractVersion = 13;" in helperd
    assert (
        'kContractPath = "/usr/local/libexec/securewave-wg-quick.contract"' in helperd
    )


def test_helper_daemon_uses_securewave_group_socket_and_allowed_uid_file():
    helperd = _read(HELPERD)

    assert 'kSocketPath = "/run/securewave/helper.sock"' in helperd
    assert 'kRuntimeDir = "/run/securewave"' in helperd
    assert 'kAllowedUsersPath = "/etc/securewave/helper-users"' in helperd
    assert 'kGroupName = "securewave"' in helperd
    assert "SO_PEERCRED" in helperd
    assert "UidAllowedByFile" in helperd
    assert 'Error("unauthorized"' in helperd


def test_helper_daemon_runs_only_absolute_allowlisted_executables():
    helperd = _read(HELPERD)

    assert "AllowlistedExecutablePath" in helperd
    assert 'G_SPAWN_DEFAULT' in helperd
    assert 'G_SPAWN_SEARCH_PATH' not in helperd
    assert 'Command executable is not allowlisted.' in helperd


def test_helper_daemon_inspects_legacy_adblock_chain_without_user_input():
    helperd = _read(HELPERD)

    assert 'kAdblockChainName = "SECUREWAVE_ADBLOCK"' in helperd
    assert 'RunCommand({"iptables", "-S", kAdblockChainName})' in helperd
    assert 'op == "firewall.adblock_status"' in helperd
    assert 'RequestFieldsAllowed(request, {"version", "op"})' in helperd
    assert '"inspection_failed"' in helperd


def test_helper_daemon_checks_ikev2_loop_rules_in_both_address_families():
    helperd = _read(HELPERD)

    assert 'ReadIpRules("-4")' in helperd
    assert 'ReadIpRules("-6")' in helperd
    assert "rules4.ok &&" in helperd
    assert "rules6.ok &&" in helperd


def test_helper_daemon_certifies_ikev2_kernel_cleanup_with_privileged_evidence():
    helperd = _read(HELPERD)

    assert 'RunCommand({"ip", "-s", "xfrm", "state"})' in helperd
    assert 'RunCommand({"ip", "xfrm", "policy"})' in helperd
    assert 'fields["xfrm_state_inspection_ok"]' in helperd
    assert 'fields["xfrm_policy_inspection_ok"]' in helperd
    assert 'fields["xfrm_esp_present"]' in helperd
    assert 'fields["xfrm_policy_present"]' in helperd
    assert "ParseXfrmStateRecords" in helperd
    assert "ParseXfrmPolicyRecords" in helperd
    assert "OwnedXfrmPairPresent" in helperd
    assert "ParseOwnedXfrmCounters" in helperd
    assert 'kIkev2InterfaceName = "nm-xfrm-sw"' in helperd
    assert 'kIkev2IfIdPath = "/run/securewave/ikev2-xfrm-if-id"' in helperd
    assert 'fields["xfrm_pair_present"]' in helperd
    assert 'fields["route_inspection_ok"]' in helperd
    assert 'fields["ipv4_full_route_present"]' in helperd
    assert 'fields["ipv6_full_route_present"]' in helperd
    assert 'fields["routing_rule_inspection_ok"]' in helperd
    assert 'fields["routing_rules_safe"]' in helperd
    assert 'fields["routing_rules_idle_safe"]' in helperd
    assert 'fields["connection_inspection_ok"]' in helperd
    assert 'fields["connection_present"]' in helperd
    assert '"inspection_failed"' in helperd
    assert '"vpn_residue_present"' in helperd


def test_helper_daemon_inspects_exact_owned_wireguard_firewall_state():
    helperd = _read(HELPERD)

    assert 'RunCommand({"nft", "list", "tables"})' in helperd
    assert 'RunCommand({"iptables-save"})' in helperd
    assert 'RunCommand({"ip6tables-save"})' in helperd
    assert 'name == "wg-quick-sw-wg"' in helperd
    assert "wg-quick(8) rule for sw-wg" in helperd
    assert 'fields["firewall_inspection_ok"]' in helperd
    assert 'fields["nft_table_present"]' in helperd
    assert 'fields["iptables_rule_present"]' in helperd
    assert 'fields["ip6tables_rule_present"]' in helperd


def test_helper_daemon_requires_recent_handshake_and_endpoint_bypass():
    helperd = _read(HELPERD)

    assert "WireGuardHandshakeEvidence" in helperd
    assert '"wg", "show", kWireGuardInterface, "latest-handshakes"' in helperd
    assert "WireGuardEndpointBypassEvidence" in helperd
    assert '"wg", "show", kWireGuardInterface, "endpoints"' in helperd
    assert '"endpoint_bypass_present"' in helperd
    assert '"handshake_present"' in helperd


def test_helper_daemon_rolls_back_a_started_tunnel_without_handshake_proof():
    helperd = _read(HELPERD)

    up_block = helperd.split('if (op == "wireguard.up") {', 1)[1].split(
        'if (op == "wireguard.down") {', 1
    )[0]
    assert "if (WaitWireGuardConnected()) {" in up_block
    assert "return WireGuardStatus();" in up_block
    assert 'RunHelper({"down", config_path});' in up_block
    assert "WireGuard start did not produce authenticated tunnel evidence" in up_block
    assert "WaitWireGuardClean()" in up_block


def test_privileged_helper_script_restricts_inputs_and_protocol_actions():
    helper = _read(HELPER)

    assert "securewave-wg-quick probe wireguard" in helper
    assert "require_safe_config_path" in helper
    assert "require_safe_runtime_file" in helper
    assert "require_sw_wg_iface" in helper
    assert 'if [[ "$iface" != "sw-wg" ]]' in helper
    assert "wireguard-transfer" in helper
    assert "openvpn-*|ikev2-*|xfrm-state" in helper


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
    assert "strongswan-starter.service" not in service
    assert tmpfiles.strip() == "d /run/securewave 0750 root securewave -"


def test_strongswan_routing_dropin_pairs_marks_for_both_daemons():
    routing = _read(STRONGSWAN_ROUTING)

    assert routing.count("fwmark = !0xdc") == 1
    assert routing.count("fwmark = 0xdc") == 1
    assert "charon {" not in routing
    assert "routing_table = 210" in routing
    assert "routing_table_prio = 210" in routing
    assert "charon-nm {" in routing


def test_install_helper_script_installs_wireguard_payload_without_polkit():
    installer = _read(INSTALLER)

    assert 'HELPER_DIR="/usr/local/libexec"' in installer
    assert 'SERVICE_FILE="/etc/systemd/system/securewave-helper.service"' in installer
    assert 'TMPFILES_FILE="/usr/lib/tmpfiles.d/securewave-helper.conf"' in installer
    assert 'AUTH_FILE="$AUTH_DIR/helper-users"' in installer
    assert 'groupadd --system "$RUNTIME_GROUP"' in installer
    assert 'usermod -a -G "$RUNTIME_GROUP" "$allowed_user"' in installer
    assert "done < /etc/passwd" not in installer
    assert "50-securewave-wg.rules" not in installer
    assert "systemctl daemon-reload" in installer
    assert "systemctl enable --now securewave-helper.service" in installer
    assert "openvpn" not in installer.lower()
    assert "strongswan" not in installer.lower()
    assert "ikev2" not in installer.lower()
    assert "systemctl try-restart strongswan-starter.service" not in installer
