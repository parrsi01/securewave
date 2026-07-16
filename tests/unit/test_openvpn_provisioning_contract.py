from pathlib import Path
import subprocess


SCRIPT = Path("infrastructure/hetzner/provision_openvpn_server.sh")


def test_openvpn_provisioning_auth_hook_is_executable_by_dropped_privilege_user():
    source = SCRIPT.read_text(encoding="utf-8")

    assert "apt-get install -y --no-install-recommends acl openvpn" in source
    assert "setfacl -m g:securewave-ovpn:x /etc/securewave" in source
    assert 'chown root:securewave-ovpn "$AUTH"' in source
    assert 'chmod 0750 "$AUTH"' in source
    assert 'chmod 0700 "$AUTH"' not in source


def test_openvpn_provisioning_script_has_valid_shell_syntax():
    result = subprocess.run(
        ["bash", "-n", str(SCRIPT)], capture_output=True, text=True, check=False
    )
    assert result.returncode == 0, result.stderr
