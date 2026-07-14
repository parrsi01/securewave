from __future__ import annotations

import shutil
import subprocess  # nosec B404
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
HELPERD = ROOT / "securewave_app/linux/helperd/securewave_helperd.cc"


@pytest.fixture(scope="module")
def helperd_harness(tmp_path_factory: pytest.TempPathFactory) -> Path:
    compiler = shutil.which("g++")
    pkg_config = shutil.which("pkg-config")
    if compiler is None or pkg_config is None:
        pytest.skip("g++ and pkg-config are required for helper daemon behavior tests")

    flags = subprocess.run(  # nosec B603
        [pkg_config, "--cflags", "--libs", "glib-2.0", "gio-2.0"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()
    build_dir = tmp_path_factory.mktemp("helperd-harness")
    source = build_dir / "helperd_harness.cc"
    binary = build_dir / "helperd_harness"
    source.write_text(
        f'''#define main securewave_helperd_daemon_main
#include "{HELPERD}"
#undef main

#include <iostream>
#include <iterator>

int main(int argc, char** argv) {{
  if (argc < 2) return 64;
  const std::string mode = argv[1];
  if (mode == "wireguard" && argc == 3) {{
    return ValidateWireGuardConfigContents(argv[2]) ? 0 : 1;
  }}
  if (mode == "openvpn" && argc == 3) {{
    return ValidateOpenVpnConfigContents(argv[2]) ? 0 : 1;
  }}
  if (mode == "openvpn-dns" && argc == 3) {{
    DnsServers servers;
    if (!ValidateOpenVpnConfigContents(argv[2], &servers)) return 1;
    std::cout << "ipv4=" << servers.ipv4.size() << "\\n";
    std::cout << "ipv6=" << servers.ipv6.size() << "\\n";
    for (const std::string& value : servers.ipv4) std::cout << value << "\\n";
    for (const std::string& value : servers.ipv6) std::cout << value << "\\n";
    return 0;
  }}
  if (mode == "ikev2-dns" && argc == 3) {{
    std::ifstream input(argv[2], std::ios::binary);
    const std::string contents(
        (std::istreambuf_iterator<char>(input)),
        std::istreambuf_iterator<char>());
    DnsServers servers;
    if (!ExtractIkev2DnsServers(contents, &servers)) return 1;
    std::cout << "ipv4=" << servers.ipv4.size() << "\\n";
    std::cout << "ipv6=" << servers.ipv6.size() << "\\n";
    for (const std::string& value : servers.ipv4) std::cout << value << "\\n";
    for (const std::string& value : servers.ipv6) std::cout << value << "\\n";
    return 0;
  }}
  if (mode == "ikev2-network") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    const Ikev2NetworkEvidence evidence = ParseIkev2NetworkEvidence(output);
    std::cout << "dns=" << evidence.dns_present << "\\n";
    return 0;
  }}
  if (mode == "uint32" && argc == 4) {{
    guint32 value = 0;
    const bool valid = ParseUint32Strict(argv[2], atoi(argv[3]), &value);
    std::cout << "valid=" << valid << "\\n";
    std::cout << "value=" << value << "\\n";
    return 0;
  }}
  if (mode == "xfrm-interface") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    guint32 if_id = 0;
    const bool valid = ParseXfrmInterfaceId(output, &if_id);
    std::cout << "valid=" << valid << "\\n";
    std::cout << "if_id=" << if_id << "\\n";
    return 0;
  }}
  if (mode == "xfrm-owned" && argc == 3) {{
    guint32 if_id = 0;
    if (!ParseUint32Strict(argv[2], 0, &if_id)) return 64;
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    const std::string delimiter = "\\n---\\n";
    const std::string::size_type split = output.find(delimiter);
    if (split == std::string::npos) return 64;
    bool state_parse_ok = false;
    bool policy_parse_ok = false;
    const std::vector<XfrmStateRecord> states =
        ParseXfrmStateRecords(output.substr(0, split), &state_parse_ok);
    const std::vector<XfrmPolicyRecord> policies = ParseXfrmPolicyRecords(
        output.substr(split + delimiter.size()), &policy_parse_ok);
    guint64 rx = 0;
    guint64 tx = 0;
    std::cout << "state_parse_ok=" << state_parse_ok << "\\n";
    std::cout << "policy_parse_ok=" << policy_parse_ok << "\\n";
    std::cout << "state_present=" << OwnedXfrmStatePresent(states, if_id)
              << "\\n";
    std::cout << "esp_present=" << OwnedXfrmEspPresent(states, if_id)
              << "\\n";
    std::cout << "policy_present=" << OwnedXfrmPolicyPresent(policies, if_id)
              << "\\n";
    std::cout << "pair_present=" << OwnedXfrmPairPresent(states, policies, if_id)
              << "\\n";
    std::cout << "counters="
              << ParseOwnedXfrmCounters(states, policies, if_id, &rx, &tx)
              << "\\n";
    std::cout << "rx=" << rx << "\\n";
    std::cout << "tx=" << tx << "\\n";
    return 0;
  }}
  if (mode == "ikev2-routes") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    const std::string delimiter = "\\n---\\n";
    const std::string::size_type split = output.find(delimiter);
    if (split == std::string::npos) return 64;
    const Ikev2RouteFamilyEvidence routes4 =
        ParseIkev2RouteFamilyEvidence(output.substr(0, split), false);
    const Ikev2RouteFamilyEvidence routes6 = ParseIkev2RouteFamilyEvidence(
        output.substr(split + delimiter.size()), true);
    std::cout << "v4_owned=" << routes4.owned_route_present << "\\n";
    std::cout << "v4_full=" << routes4.full_route_present << "\\n";
    std::cout << "v4_conflict=" << routes4.conflicting_full_route << "\\n";
    std::cout << "v6_owned=" << routes6.owned_route_present << "\\n";
    std::cout << "v6_full=" << routes6.full_route_present << "\\n";
    std::cout << "v6_conflict=" << routes6.conflicting_full_route << "\\n";
    return 0;
  }}
  if (mode == "ikev2-rules") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    const Ikev2RuleEvidence evidence = ParseIkev2RuleEvidence(output);
    std::cout << "safe_count=" << evidence.expected_safe_count << "\\n";
    std::cout << "unexpected=" << evidence.unexpected_table_210_rule << "\\n";
    std::cout << "safe=" << Ikev2RuleEvidenceSafe(evidence) << "\\n";
    return 0;
  }}
  if (mode == "ikev2-idle-rules") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    const std::string delimiter = "\\n---\\n";
    const std::string::size_type split = output.find(delimiter);
    if (split == std::string::npos) return 64;
    const Ikev2RuleEvidence rules4 =
        ParseIkev2RuleEvidence(output.substr(0, split));
    const Ikev2RuleEvidence rules6 = ParseIkev2RuleEvidence(
        output.substr(split + delimiter.size()));
    std::cout << "idle_safe=" << Ikev2RuleEvidenceIdleSafe(rules4, rules6)
              << "\\n";
    return 0;
  }}
  if (mode == "wg-nft-output") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "present=" << WgQuickNftTablePresent(output) << "\\n";
    return 0;
  }}
  if (mode == "wg-iptables-output") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "present=" << WgQuickIptablesRulePresent(output) << "\\n";
    return 0;
  }}
  if (mode == "wg-ipv4-block-output") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "present=" << WireGuardIpv4KillSwitchPresent(output) << "\\n";
    return 0;
  }}
  if (mode == "wg-ipv6-block-output") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "present=" << WireGuardIpv6BlockPresent(output) << "\\n";
    return 0;
  }}
  if (mode == "ikev2-ipv6-block-output") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "present=" << Ikev2Ipv6BlockRulePresent(output) << "\\n";
    return 0;
  }}
  if (mode == "resolved-domain-output") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "route_all="
              << OutputContainsWhitespaceDelimitedToken(output, "~.")
              << "\\n";
    return 0;
  }}
  if (mode == "ikev2-clean" && argc == 17) {{
    const bool clean = Ikev2DisconnectedStateClean(
        std::string(argv[2]) == "1",
        std::string(argv[3]) == "1",
        std::string(argv[4]) == "1",
        std::string(argv[5]) == "1",
        std::string(argv[6]) == "1",
        std::string(argv[7]) == "1",
        std::string(argv[8]) == "1",
        std::string(argv[9]) == "1",
        std::string(argv[10]) == "1",
        std::string(argv[11]) == "1",
        std::string(argv[12]) == "1",
        std::string(argv[13]) == "1",
        std::string(argv[14]) == "1",
        std::string(argv[15]) == "1",
        std::string(argv[16]) == "1");
    std::cout << "clean=" << clean << "\\n";
    return 0;
  }}
  if (mode == "ikev2-connections") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "present=" << NmcliListHasExactIkev2(output) << "\\n";
    return 0;
  }}
  if (mode == "request") {{
    const std::string body(
        std::istreambuf_iterator<char>(std::cin),
        std::istreambuf_iterator<char>());
    const ParsedFields parsed = ParseFields(body);
    if (!parsed.valid) {{
      std::cout << "ok=false\\ncode=invalid_request\\n";
      return 0;
    }}
    std::cout << SerializeFields(HandleRequest(parsed.fields, getuid()));
    return 0;
  }}
  return 64;
}}
''',
        encoding="utf-8",
    )
    subprocess.run(  # nosec B603
        [
            compiler,
            "-std=c++14",
            "-Wall",
            "-Wextra",
            "-Werror",
            str(source),
            "-o",
            str(binary),
            *flags,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return binary


def _run_request(binary: Path, body: str) -> dict[str, str]:
    result = subprocess.run(  # nosec B603
        [str(binary), "request"],
        input=body,
        check=True,
        capture_output=True,
        text=True,
    )
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


@pytest.mark.parametrize(
    "body",
    [
        "version=1\nop\n",
        "version=1\nop=probe\nop=wireguard.status\n",
        "version=1\nOp=probe\n",
        "version=1\n=probe\n",
    ],
)
def test_helper_rejects_malformed_or_duplicate_fields(helperd_harness: Path, body: str):
    response = _run_request(helperd_harness, body)

    assert response["ok"] == "false"
    assert response["code"] == "invalid_request"


def test_helper_rejects_unknown_fields_and_operations(helperd_harness: Path):
    unexpected = _run_request(
        helperd_harness,
        "version=1\nop=wireguard.status\ncommand=id\n",
    )
    arbitrary = _run_request(
        helperd_harness,
        "version=1\nop=shell\ncommand=id\n",
    )
    firewall_extra = _run_request(
        helperd_harness,
        "version=1\nop=firewall.adblock_status\ncommand=id\n",
    )

    assert unexpected["code"] == "invalid_request"
    assert arbitrary["code"] == "invalid_operation"
    assert firewall_extra["code"] == "invalid_request"


def _validate_config(binary: Path, mode: str, path: Path) -> bool:
    return (
        subprocess.run(  # nosec B603
            [str(binary), mode, str(path)],
            check=False,
            capture_output=True,
            text=True,
        ).returncode
        == 0
    )


def test_wireguard_config_rejects_arbitrary_hooks(
    helperd_harness: Path, tmp_path: Path
):
    config = tmp_path / "sw-wg.conf"
    safe = """[Interface]
PrivateKey = test-private-key
Address = 10.0.0.2/32
[Peer]
PublicKey = test-public-key
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.invalid:51820
"""
    config.write_text(safe, encoding="utf-8")
    assert _validate_config(helperd_harness, "wireguard", config)

    config.write_text(
        safe.replace(
            "Address = 10.0.0.2/32",
            "Address = 10.0.0.2/32\nPostUp = /bin/sh -c id",
        ),
        encoding="utf-8",
    )
    assert not _validate_config(helperd_harness, "wireguard", config)


def test_wireguard_config_accepts_only_known_kill_switch_hook(
    helperd_harness: Path, tmp_path: Path
):
    config = tmp_path / "sw-wg.conf"
    config.write_text(
        """[Interface]
PrivateKey = test-private-key
Address = 10.0.0.2/32
PostUp = sh -c 'command -v iptables >/dev/null 2>&1 && iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -m comment --comment securewave-wireguard-ipv4-kill-switch-v1 -j REJECT'
PostDown = sh -c 'command -v iptables >/dev/null 2>&1 && iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -m comment --comment securewave-wireguard-ipv4-kill-switch-v1 -j REJECT || true'
PostUp = sh -c 'command -v ip6tables >/dev/null 2>&1 && ip6tables -I OUTPUT -d 2000::/3 -m mark ! --mark $(wg show %i fwmark) -m comment --comment securewave-wireguard-ipv6-block-v1 -j REJECT --reject-with icmp6-adm-prohibited'
PostDown = sh -c 'command -v ip6tables >/dev/null 2>&1 && ip6tables -D OUTPUT -d 2000::/3 -m mark ! --mark $(wg show %i fwmark) -m comment --comment securewave-wireguard-ipv6-block-v1 -j REJECT --reject-with icmp6-adm-prohibited || true'
[Peer]
PublicKey = test-public-key
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.invalid:51820
""",
        encoding="utf-8",
    )

    assert _validate_config(helperd_harness, "wireguard", config)


@pytest.mark.parametrize(
    "directive",
    [
        "script-security 2",
        "up /bin/sh",
        "plugin /tmp/untrusted.so",
        "config /tmp/extra.conf",
        "log /etc/unsafe.log",
        "auth-user-pass /tmp/credentials",
    ],
)
def test_openvpn_config_rejects_privileged_directives(
    helperd_harness: Path, tmp_path: Path, directive: str
):
    config = tmp_path / "securewave.ovpn"
    config.write_text(
        f"client\ndev tun\nproto udp\nremote vpn.example.invalid 1194\n{directive}\n",
        encoding="utf-8",
    )

    assert not _validate_config(helperd_harness, "openvpn", config)


def test_openvpn_config_accepts_backend_profile_shape(
    helperd_harness: Path, tmp_path: Path
):
    config = tmp_path / "securewave.ovpn"
    config.write_text(
        """client
dev tun
proto udp
remote vpn.example.invalid 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth-user-pass
auth-nocache
ifconfig-ipv6 fd53:6563:7572:6577::2/64 fd53:6563:7572:6577::1
redirect-gateway def1 ipv6
block-ipv6
dhcp-option DNS 1.1.1.1
verb 3
<ca>
test-ca-data
</ca>
""",
        encoding="utf-8",
    )

    assert _validate_config(helperd_harness, "openvpn", config)


@pytest.mark.parametrize(
    "invalid_line",
    (
        "",
        "block-ipv6 extra",
        "ifconfig-ipv6 fd00::2/64 fd00::1",
        "redirect-gateway def1",
        "redirect-gateway ipv6 def1",
    ),
)
def test_openvpn_config_requires_exact_public_ipv6_block_contract(
    helperd_harness: Path,
    tmp_path: Path,
    invalid_line: str,
):
    required = [
        "ifconfig-ipv6 fd53:6563:7572:6577::2/64 fd53:6563:7572:6577::1",
        "redirect-gateway def1 ipv6",
        "block-ipv6",
    ]
    replacement_index = {
        "": 2,
        "block-ipv6 extra": 2,
        "ifconfig-ipv6 fd00::2/64 fd00::1": 0,
        "redirect-gateway def1": 1,
        "redirect-gateway ipv6 def1": 1,
    }[invalid_line]
    required[replacement_index] = invalid_line
    config = tmp_path / "securewave.ovpn"
    config.write_text(
        "client\ndev tun\ndhcp-option DNS 1.1.1.1\n"
        + "\n".join(line for line in required if line)
        + "\n",
        encoding="utf-8",
    )

    assert not _validate_config(helperd_harness, "openvpn", config)


def test_openvpn_config_cannot_select_a_different_privileged_link(
    helperd_harness: Path, tmp_path: Path
):
    config = tmp_path / "securewave.ovpn"
    config.write_text(
        "client\ndev tun9\ndhcp-option DNS 1.1.1.1\n",
        encoding="utf-8",
    )

    assert not _validate_config(helperd_harness, "openvpn", config)


def test_openvpn_config_rejects_inline_plaintext_credentials(
    helperd_harness: Path, tmp_path: Path
):
    config = tmp_path / "securewave.ovpn"
    config.write_text(
        """client
dev tun
remote vpn.example.invalid 1194
<auth-user-pass>
test-user
test-password
</auth-user-pass>
""",
        encoding="utf-8",
    )

    assert not _validate_config(helperd_harness, "openvpn", config)


def test_openvpn_config_requires_literal_dns_and_canonicalizes_families(
    helperd_harness: Path, tmp_path: Path
):
    config = tmp_path / "securewave.ovpn"
    config.write_text(
        "client\ndev tun\n"
        "ifconfig-ipv6 fd53:6563:7572:6577::2/64 fd53:6563:7572:6577::1\n"
        "redirect-gateway def1 ipv6\nblock-ipv6\n"
        "dhcp-option DNS 1.1.1.1\n"
        "dhcp-option DNS 2606:4700:4700:0:0:0:0:1111\n",
        encoding="utf-8",
    )

    valid = subprocess.run(  # nosec B603
        [str(helperd_harness), "openvpn-dns", str(config)],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "ipv4=1" in valid.stdout
    assert "ipv6=1" in valid.stdout
    assert "2606:4700:4700::1111" in valid.stdout

    for value in (
        "",
        "resolver.example",
        "999.999.999.999",
        "2001:::1",
        "1.1.1.1;id",
        "1.1.1.1 extra",
    ):
        line = "" if not value else f"dhcp-option DNS {value}\n"
        config.write_text(
            "client\ndev tun\n"
            "ifconfig-ipv6 fd53:6563:7572:6577::2/64 "
            "fd53:6563:7572:6577::1\n"
            "redirect-gateway def1 ipv6\nblock-ipv6\n"
            f"{line}",
            encoding="utf-8",
        )
        assert not _validate_config(helperd_harness, "openvpn", config)


def test_ikev2_dns_marker_is_required_unique_and_literal(
    helperd_harness: Path, tmp_path: Path
):
    config = tmp_path / "securewave-ikev2.conf"
    config.write_text(
        "connections {}\n# dns = 1.1.1.1,2606:4700:4700::1111\n",
        encoding="utf-8",
    )
    valid = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-dns", str(config)],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "ipv4=1" in valid.stdout
    assert "ipv6=1" in valid.stdout

    invalid_contents = (
        "connections {}\n",
        "# dns = resolver.example\n",
        "# dns = 999.999.999.999\n",
        "# dns = 2001:::1\n",
        "# dns = 1.1.1.1;id\n",
        "# dns = 1.1.1.1,\n",
        "# dns = 1.1.1.1\n# dns = 1.0.0.1\n",
    )
    for contents in invalid_contents:
        config.write_text(contents, encoding="utf-8")
        result = subprocess.run(  # nosec B603
            [str(helperd_harness), "ikev2-dns", str(config)],
            check=False,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1


def test_ikev2_network_metadata_is_dns_only(helperd_harness: Path):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-network"],
        input=(
            "IP4.DNS[1]:1.1.1.1\n"
            "IP4.ROUTE[1]:dst = 0.0.0.0/0, nh = 0.0.0.0\n"
        ),
        check=True,
        capture_output=True,
        text=True,
    )
    assert "dns=1" in result.stdout
    assert "route=" not in result.stdout


@pytest.mark.parametrize(
    ("raw", "base", "valid", "value"),
    (
        ("14", 10, True, 14),
        ("0x2a", 0, True, 42),
        ("14junk", 10, False, 0),
        ("-1", 10, False, 0),
        ("+14", 10, False, 0),
        ("0", 10, False, 0),
        ("4294967296", 10, False, 0),
        ("", 10, False, 0),
    ),
)
def test_uint32_parser_rejects_malformed_contract_and_if_id_values(
    helperd_harness: Path,
    raw: str,
    base: int,
    valid: bool,
    value: int,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "uint32", raw, str(base)],
        check=True,
        capture_output=True,
        text=True,
    )

    assert (f"valid={int(valid)}" in result.stdout) is True
    assert f"value={value}" in result.stdout


@pytest.mark.parametrize(
    ("output", "valid", "if_id"),
    (
        (
            "2: nm-xfrm-sw@NONE: <NOARP,UP> mtu 1400\n"
            "    link/none promiscuity 0\n"
            "    xfrm if_id 0x2a addrgenmode eui64\n",
            True,
            42,
        ),
        ("2: nm-xfrm-sw: <UP> mtu 1400\n    tun type tun\n", False, 0),
        ("2: nm-xfrm-sw: <UP>\n    xfrm if_id -1\n", False, 0),
        ("2: nm-xfrm-sw: <UP>\n    xfrm if_id 0x2ajunk\n", False, 0),
    ),
)
def test_xfrm_interface_parser_requires_one_strict_kernel_if_id(
    helperd_harness: Path,
    output: str,
    valid: bool,
    if_id: int,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "xfrm-interface"],
        input=output,
        check=True,
        capture_output=True,
        text=True,
    )

    assert f"valid={int(valid)}" in result.stdout
    assert f"if_id={if_id}" in result.stdout


def _owned_xfrm_fixture(
    *,
    if_id: str = "0x2a",
    output_mark: str = "0xdc/0xffffffff",
    inbound_reqid: int = 7,
) -> str:
    states = (
        "src 192.0.2.2 dst 198.51.100.7\n"
        "    proto esp spi 0x00000100(256) reqid 7(0x00000007) mode tunnel\n"
        f"    output-mark {output_mark}\n"
        f"    if_id {if_id}\n"
        "    lifetime current:\n"
        "      222(bytes), 2(packets)\n"
        "src 198.51.100.7 dst 192.0.2.2\n"
        f"    proto esp spi 0x00000200(512) reqid {inbound_reqid} mode tunnel\n"
        f"    if_id {if_id}\n"
        "    lifetime current:\n"
        "      111(bytes), 1(packets)\n"
    )
    policies = (
        "src 10.45.0.2/32 dst 0.0.0.0/0\n"
        "    dir out priority 371327 ptype main\n"
        "    tmpl src 192.0.2.2 dst 198.51.100.7\n"
        "        proto esp reqid 7 mode tunnel\n"
        f"    if_id {if_id}\n"
        "src 0.0.0.0/0 dst 10.45.0.2/32\n"
        "    dir in priority 371327 ptype main\n"
        "    tmpl src 198.51.100.7 dst 192.0.2.2\n"
        f"        proto esp reqid {inbound_reqid} mode tunnel\n"
        f"    if_id {if_id}\n"
    )
    return f"{states}\n---\n{policies}"


def test_xfrm_evidence_correlates_owned_pair_and_directional_counters(
    helperd_harness: Path,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "xfrm-owned", "0x2a"],
        input=_owned_xfrm_fixture(),
        check=True,
        capture_output=True,
        text=True,
    )

    assert "state_parse_ok=1" in result.stdout
    assert "policy_parse_ok=1" in result.stdout
    assert "state_present=1" in result.stdout
    assert "esp_present=1" in result.stdout
    assert "policy_present=1" in result.stdout
    assert "pair_present=1" in result.stdout
    assert "counters=1" in result.stdout
    assert "rx=111" in result.stdout
    assert "tx=222" in result.stdout


def test_xfrm_evidence_ignores_complete_foreign_sa_and_policy(
    helperd_harness: Path,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "xfrm-owned", "0x2a"],
        input=_owned_xfrm_fixture(if_id="0xdead"),
        check=True,
        capture_output=True,
        text=True,
    )

    assert "state_parse_ok=1" in result.stdout
    assert "policy_parse_ok=1" in result.stdout
    assert "state_present=0" in result.stdout
    assert "esp_present=0" in result.stdout
    assert "policy_present=0" in result.stdout
    assert "pair_present=0" in result.stdout
    assert "counters=0" in result.stdout
    assert "rx=0" in result.stdout
    assert "tx=0" in result.stdout


@pytest.mark.parametrize(
    "fixture",
    (
        _owned_xfrm_fixture(output_mark="0xdc/0xffffff00"),
        _owned_xfrm_fixture(inbound_reqid=8),
    ),
)
def test_xfrm_evidence_rejects_unsafe_mark_or_unmatched_child_sa(
    helperd_harness: Path,
    fixture: str,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "xfrm-owned", "0x2a"],
        input=fixture,
        check=True,
        capture_output=True,
        text=True,
    )

    assert "pair_present=0" in result.stdout
    assert "counters=0" in result.stdout


def test_xfrm_evidence_fails_parse_on_malformed_owned_if_id(
    helperd_harness: Path,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "xfrm-owned", "0x2a"],
        input=_owned_xfrm_fixture(if_id="0x2ajunk"),
        check=True,
        capture_output=True,
        text=True,
    )

    assert "state_parse_ok=0" in result.stdout
    assert "policy_parse_ok=0" in result.stdout
    assert "pair_present=0" in result.stdout


@pytest.mark.parametrize(
    ("routes4", "routes6", "expected"),
    (
        (
            "default dev nm-xfrm-sw table 210 scope link\n",
            "default dev nm-xfrm-sw table 210 metric 1024 pref medium\n",
            ("v4_owned=1", "v4_full=1", "v4_conflict=0",
             "v6_owned=1", "v6_full=1", "v6_conflict=0"),
        ),
        (
            "0.0.0.0/1 dev nm-xfrm-sw table 210\n"
            "128.0.0.0/1 dev nm-xfrm-sw table 210\n",
            "::/1 dev nm-xfrm-sw table 210\n"
            "8000::/1 dev nm-xfrm-sw table 210\n",
            ("v4_owned=1", "v4_full=1", "v4_conflict=0",
             "v6_owned=1", "v6_full=1", "v6_conflict=0"),
        ),
        (
            "default dev nm-xfrm-other table 210\n",
            "default dev nm-xfrm-sw table 210\n",
            ("v4_owned=0", "v4_full=0", "v4_conflict=1",
             "v6_owned=1", "v6_full=1", "v6_conflict=0"),
        ),
        (
            "10.0.0.0/8 dev nm-xfrm-sw table 210\n",
            "",
            ("v4_owned=1", "v4_full=0", "v4_conflict=0",
             "v6_owned=0", "v6_full=0", "v6_conflict=0"),
        ),
    ),
)
def test_ikev2_route_parser_requires_exact_owned_dual_stack_full_routes(
    helperd_harness: Path,
    routes4: str,
    routes6: str,
    expected: tuple[str, ...],
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-routes"],
        input=f"{routes4}\n---\n{routes6}",
        check=True,
        capture_output=True,
        text=True,
    )

    for field in expected:
        assert field in result.stdout


@pytest.mark.parametrize(
    ("output", "safe_count", "unexpected", "safe"),
    (
        ("210: not from all fwmark 0xdc lookup 210\n", 1, 0, 1),
        ("210: from all not fwmark 0xdc/0xffffffff table 210\n", 1, 0, 1),
        ("210: from all lookup 210\n", 0, 1, 0),
        ("211: not from all fwmark 0xdc lookup 210\n", 0, 1, 0),
        ("", 0, 0, 0),
    ),
)
def test_ikev2_rule_parser_requires_exact_safe_charon_nm_rule(
    helperd_harness: Path,
    output: str,
    safe_count: int,
    unexpected: int,
    safe: int,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-rules"],
        input=output,
        check=True,
        capture_output=True,
        text=True,
    )

    assert f"safe_count={safe_count}" in result.stdout
    assert f"unexpected={unexpected}" in result.stdout
    assert f"safe={safe}" in result.stdout


@pytest.mark.parametrize(
    ("rules4", "rules6", "expected"),
    (
        ("", "", True),
        (
            "210: not from all fwmark 0xdc lookup 210\n",
            "210: not from all fwmark 0xdc lookup 210\n",
            True,
        ),
        ("210: not from all fwmark 0xdc lookup 210\n", "", False),
        (
            "210: not from all fwmark 0xdc lookup 210\n" * 2,
            "210: not from all fwmark 0xdc lookup 210\n",
            False,
        ),
        ("210: from all lookup 210\n", "", False),
    ),
)
def test_ikev2_idle_rule_parser_allows_only_paired_or_absent_safe_rules(
    helperd_harness: Path,
    rules4: str,
    rules6: str,
    expected: bool,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-idle-rules"],
        input=f"{rules4}\n---\n{rules6}",
        check=True,
        capture_output=True,
        text=True,
    )

    assert ("idle_safe=1" in result.stdout) is expected


_CLEAN_IKEV2_FLAGS = (
    "1", "0", "0",  # exact connection inspected, absent, inactive
    "1", "0",  # exact XFRM interface inspected and absent
    "1", "0",  # owned state inspected and absent
    "1", "0",  # owned policy inspected and absent
    "1", "0",  # owned table-210 routes inspected and absent
    "1", "0",  # owned public-IPv6 block inspected and absent
    "1", "1",  # rules inspected and safely paired-or-absent
)


@pytest.mark.parametrize(
    ("flags", "expected"),
    [
        (_CLEAN_IKEV2_FLAGS, True),
        *[
            (
                tuple(
                    ("0" if value == "1" else "1") if index == changed else value
                    for index, value in enumerate(_CLEAN_IKEV2_FLAGS)
                ),
                False,
            )
            for changed in range(len(_CLEAN_IKEV2_FLAGS))
        ],
    ],
)
def test_ikev2_clean_disconnect_requires_empty_owned_link_route_and_xfrm(
    helperd_harness: Path,
    flags: tuple[str, ...],
    expected: bool,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-clean", *flags],
        check=True,
        capture_output=True,
        text=True,
    )

    assert ("clean=1" in result.stdout) is expected


@pytest.mark.parametrize(
    ("output", "expected"),
    [
        ("SecureWave-IKEv2:vpn\n", True),
        ("Other:vpn\nSecureWave-IKEv2:vpn\n", True),
        ("SecureWave-IKEv2:ethernet\n", False),
        ("SecureWave-IKEv2-copy:vpn\n", False),
        ("prefix-SecureWave-IKEv2:vpn\n", False),
        ("", False),
    ],
)
def test_ikev2_connection_parser_requires_exact_name_and_vpn_type(
    helperd_harness: Path,
    output: str,
    expected: bool,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-connections"],
        input=output,
        check=True,
        capture_output=True,
        text=True,
    )

    assert ("present=1" in result.stdout) is expected


@pytest.mark.parametrize(
    ("output", "expected"),
    [
        ("table ip wg-quick-sw-wg\n", True),
        ("table ip6 wg-quick-sw-wg\n", True),
        ("table inet wg-quick-sw-wg\n", True),
        ("table ip wg-quick-other\n", False),
        ("table ip prefix-wg-quick-sw-wg\n", False),
        ("table bridge wg-quick-sw-wg\n", False),
        ("table ip wg-quick-sw-wg extra\n", False),
    ],
)
def test_wireguard_nft_residue_parser_matches_only_exact_owned_tables(
    helperd_harness: Path,
    output: str,
    expected: bool,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "wg-nft-output"],
        input=output,
        check=True,
        capture_output=True,
        text=True,
    )

    assert ("present=1" in result.stdout) is expected


@pytest.mark.parametrize(
    ("rule", "expected"),
    [
        (
            '-A PREROUTING -m comment --comment "wg-quick(8) rule for sw-wg" -j DROP\n',
            True,
        ),
        (
            '-A PREROUTING -m comment --comment "wg-quick(8) rule for other" -j DROP\n',
            False,
        ),
        (
            '-A PREROUTING -m comment --comment "prefix wg-quick(8) rule for sw-wg" -j DROP\n',
            False,
        ),
        (
            '-D PREROUTING -m comment --comment "wg-quick(8) rule for sw-wg" -j DROP\n',
            False,
        ),
    ],
)
def test_wireguard_iptables_residue_parser_matches_only_exact_owned_comments(
    helperd_harness: Path,
    rule: str,
    expected: bool,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "wg-iptables-output"],
        input=rule,
        check=True,
        capture_output=True,
        text=True,
    )

    assert ("present=1" in result.stdout) is expected


@pytest.mark.parametrize(
    ("mode", "rule", "expected"),
    (
        (
            "wg-ipv4-block-output",
            '-A OUTPUT ! -o sw-wg -m mark ! --mark 0xca6c '
            '-m addrtype ! --dst-type LOCAL -m comment --comment '
            '"securewave-wireguard-ipv4-kill-switch-v1" -j REJECT\n',
            True,
        ),
        (
            "wg-ipv6-block-output",
            '-A OUTPUT -d 2000::/3 -m mark ! --mark 0xca6c/0xffffffff '
            '-m comment --comment "securewave-wireguard-ipv6-block-v1" '
            '-j REJECT --reject-with icmp6-adm-prohibited\n',
            True,
        ),
        (
            "ikev2-ipv6-block-output",
            '-A OUTPUT -d 2000::/3 -m mark ! --mark 0xdc/0xffffffff '
            '-m comment --comment "securewave-ikev2-ipv6-block-v1" '
            '-j REJECT --reject-with icmp6-adm-prohibited\n',
            True,
        ),
        (
            "wg-ipv6-block-output",
            '-A OUTPUT -d ::/0 -m mark ! --mark 0xca6c '
            '-m comment --comment "securewave-wireguard-ipv6-block-v1" '
            '-j REJECT --reject-with icmp6-adm-prohibited\n',
            False,
        ),
        (
            "ikev2-ipv6-block-output",
            '-A OUTPUT -d 2000::/3 -m mark ! --mark 0xdd '
            '-m comment --comment "securewave-ikev2-ipv6-block-v1" '
            '-j REJECT --reject-with icmp6-adm-prohibited\n',
            False,
        ),
    ),
)
def test_ipv6_block_parsers_require_exact_owned_rule(
    helperd_harness: Path,
    mode: str,
    rule: str,
    expected: bool,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), mode],
        input=rule,
        check=True,
        capture_output=True,
        text=True,
    )

    assert ("present=1" in result.stdout) is expected


@pytest.mark.parametrize(
    ("output", "expected"),
    [
        ("Link 7 (tun-securewave): ~.\n", True),
        ("Link 7 (tun-securewave): ~corp.example ~.\n", True),
        ("Link 7 (tun-securewave): ~.evil\n", False),
        ("Link 7 (tun-securewave): prefix~.\n", False),
        ("Link 7 (tun-securewave): ~corp.example\n", False),
    ],
)
def test_resolved_route_all_domain_requires_exact_whitespace_delimited_token(
    helperd_harness: Path,
    output: str,
    expected: bool,
):
    result = subprocess.run(  # nosec B603
        [str(helperd_harness), "resolved-domain-output"],
        input=output,
        check=True,
        capture_output=True,
        text=True,
    )

    assert ("route_all=1" in result.stdout) is expected
