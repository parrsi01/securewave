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
    return subprocess.run(  # nosec B603
        [str(binary), mode, str(path)],
        check=False,
        capture_output=True,
        text=True,
    ).returncode == 0


def test_wireguard_config_rejects_arbitrary_hooks(helperd_harness: Path, tmp_path: Path):
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
verb 3
<ca>
test-ca-data
</ca>
""",
        encoding="utf-8",
    )

    assert _validate_config(helperd_harness, "openvpn", config)


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
