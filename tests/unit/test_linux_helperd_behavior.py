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
    std::cout << "route=" << evidence.route_present << "\\n";
    return 0;
  }}
  if (mode == "xfrm-output") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "present=" << XfrmOutputPresent(output) << "\\n";
    std::cout << "esp=" << XfrmHasEsp(output) << "\\n";
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
  if (mode == "resolved-domain-output") {{
    const std::string output(
        (std::istreambuf_iterator<char>(std::cin)),
        std::istreambuf_iterator<char>());
    std::cout << "route_all="
              << OutputContainsWhitespaceDelimitedToken(output, "~.")
              << "\\n";
    return 0;
  }}
  if (mode == "ikev2-clean" && argc == 9) {{
    const bool clean = Ikev2DisconnectedStateClean(
        std::string(argv[2]) == "1",
        std::string(argv[3]) == "1",
        std::string(argv[4]) == "1",
        std::string(argv[5]) == "1",
        std::string(argv[6]) == "1",
        std::string(argv[7]) == "1",
        std::string(argv[8]) == "1");
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
PostUp = sh -c 'command -v iptables >/dev/null 2>&1 && iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT'
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
redirect-gateway def1
dhcp-option DNS 1.1.1.1
verb 3
<ca>
test-ca-data
</ca>
""",
        encoding="utf-8",
    )

    assert _validate_config(helperd_harness, "openvpn", config)


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
        "client\ndev tun\ndhcp-option DNS 1.1.1.1\n"
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
        config.write_text(f"client\ndev tun\n{line}", encoding="utf-8")
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


def test_ikev2_runtime_requires_separate_indexed_dns_and_route_fields(
    helperd_harness: Path,
):
    dns_only = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-network"],
        input="IP4.DNS[1]:1.1.1.1\nIP4.ROUTE[1]:--\n",
        check=True,
        capture_output=True,
        text=True,
    )
    assert "dns=1" in dns_only.stdout
    assert "route=0" in dns_only.stdout

    complete = subprocess.run(  # nosec B603
        [str(helperd_harness), "ikev2-network"],
        input=("IP4.DNS[1]:1.1.1.1\nIP4.ROUTE[1]:dst = 0.0.0.0/0, nh = 0.0.0.0\n"),
        check=True,
        capture_output=True,
        text=True,
    )
    assert "dns=1" in complete.stdout
    assert "route=1" in complete.stdout


def test_xfrm_output_presence_and_esp_detection_are_independent(
    helperd_harness: Path,
):
    empty = subprocess.run(  # nosec B603
        [str(helperd_harness), "xfrm-output"],
        input=" \n",
        check=True,
        capture_output=True,
        text=True,
    )
    assert "present=0" in empty.stdout
    assert "esp=0" in empty.stdout

    policy = subprocess.run(  # nosec B603
        [str(helperd_harness), "xfrm-output"],
        input="src 10.0.0.0/24 dst 0.0.0.0/0 dir out\n",
        check=True,
        capture_output=True,
        text=True,
    )
    assert "present=1" in policy.stdout
    assert "esp=0" in policy.stdout

    state = subprocess.run(  # nosec B603
        [str(helperd_harness), "xfrm-output"],
        input="src 192.0.2.1 dst 198.51.100.1 proto esp spi 0x1\n",
        check=True,
        capture_output=True,
        text=True,
    )
    assert "present=1" in state.stdout
    assert "esp=1" in state.stdout


@pytest.mark.parametrize(
    ("flags", "expected"),
    [
        (("1", "0", "0", "1", "0", "1", "0"), True),
        (("0", "0", "0", "1", "0", "1", "0"), False),
        (("1", "1", "0", "1", "0", "1", "0"), False),
        (("1", "0", "1", "1", "0", "1", "0"), False),
        (("1", "0", "0", "0", "0", "1", "0"), False),
        (("1", "0", "0", "1", "1", "1", "0"), False),
        (("1", "0", "0", "1", "0", "0", "0"), False),
        (("1", "0", "0", "1", "0", "1", "1"), False),
    ],
)
def test_ikev2_clean_disconnect_requires_successful_empty_state_and_policy(
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
