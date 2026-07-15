"""Static contracts for the dedicated IKEv2 gateway and disposable lab."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROVISIONER = ROOT / "infrastructure/hetzner/provision_ikev2_server.sh"
LAB = ROOT / "scripts/ikev2_container_lab.sh"


def test_ikev2_ed25519_public_key_derivation_uses_strongswan_auto_detection():
    """`pki --pub` rejects `--type ed25519` on supported strongSwan 5.9.x."""
    for source in (PROVISIONER.read_text(encoding="utf-8"), LAB.read_text(encoding="utf-8")):
        assert "pki --pub --in" in source
        assert "pki --pub --in \"$SERVER_KEY\" |" in source or "pki --pub --in \"$LAB_DIR/pki/gateway-key.pem\" |" in source
        assert "pki --pub --in \"$SERVER_KEY\" --type ed25519" not in source
        assert "pki --pub --in \"$LAB_DIR/pki/gateway-key.pem\" --type ed25519" not in source


def test_ikev2_gateway_and_lab_keep_credentials_and_egress_isolated():
    provisioner = PROVISIONER.read_text(encoding="utf-8")
    lab = LAB.read_text(encoding="utf-8")

    assert "securewave-ikev2-credential" in provisioner
    assert 'op="${1:-}"' in provisioner
    assert 'IFS= read -r password' in provisioner
    assert '--load-all --clear --noprompt' in provisioner
    assert 'libstrongswan-standard-plugins' in provisioner
    assert 'libstrongswan-standard-plugins' in (ROOT / "infrastructure/ikev2_lab/Dockerfile").read_text(encoding="utf-8")
    assert 'sudoers.d/securewave-ikev2' in provisioner
    assert 'docker network create --internal' in lab
    assert 'docker ps -aq --filter label=securewave.lab=ikev2' in lab
    assert 'LAB_PARENT="${XDG_CACHE_HOME:-$HOME/.cache}/securewave-ikev2-lab"' in lab
    assert 'SECUREWAVE_LAB_SKIP_CHARON=1' in lab
    assert 'timeout --signal=KILL 180' in lab
    assert '172.30.0.3:8443' in lab
    assert 'observed_source' in lab
    assert 'invalid EAP credential unexpectedly established' in lab
