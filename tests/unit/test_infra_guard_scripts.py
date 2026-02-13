import os
import shutil
import subprocess
from pathlib import Path


def test_check_guardrails_skips_when_terraform_missing(tmp_path):
    script = Path("infra/hetzner/check_guardrails.sh")
    shim_dir = tmp_path / "shim"
    shim_dir.mkdir()
    (shim_dir / "dirname").symlink_to("/usr/bin/dirname")
    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env={**os.environ, "PATH": str(shim_dir)},
        check=False,
    )
    assert result.returncode == 0
    assert "WARNING: terraform not found" in result.stderr


def test_check_guardrails_fails_when_infra_misconfigured(tmp_path):
    src = Path("infra/hetzner/check_guardrails.sh")
    local_script = tmp_path / "check_guardrails.sh"
    shutil.copy(src, local_script)
    local_script.chmod(0o755)
    # Intentionally omit versions.tf to simulate misconfigured infra dir.
    (tmp_path / "main.tf").write_text("terraform {}\n", encoding="utf-8")
    (tmp_path / "variables.tf").write_text("", encoding="utf-8")
    shim_dir = tmp_path / "shim"
    shim_dir.mkdir()
    (shim_dir / "dirname").symlink_to("/usr/bin/dirname")

    result = subprocess.run(
        ["/bin/bash", str(local_script)],
        capture_output=True,
        text=True,
        env={**os.environ, "PATH": str(shim_dir)},
        check=False,
    )
    assert result.returncode != 0
    assert "Infra misconfigured" in result.stderr


def _write_fake_terraform(path: Path) -> None:
    fake = path / "terraform"
    fake.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    fake.chmod(0o755)


def _write_fake_guardrails(tf_dir: Path) -> None:
    script = tf_dir / "check_guardrails.sh"
    script.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    script.chmod(0o755)


def test_release_hetzner_blocks_disallowed_server_type(tmp_path):
    tf_dir = tmp_path / "tf"
    tf_dir.mkdir()
    _write_fake_guardrails(tf_dir)
    _write_fake_terraform(tmp_path)

    script = Path("scripts/release_hetzner.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), "plan"],
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "PATH": f"{tmp_path}:{os.environ.get('PATH', '')}",
            "TF_DIR": str(tf_dir),
            "HETZNER_API_TOKEN": "dummy",
            "TF_VAR_server_type": "cx41",
        },
        check=False,
    )
    assert result.returncode != 0
    assert "Allowed: cx23 or cx33" in result.stderr


def test_release_hetzner_enforces_monthly_instance_cap(tmp_path):
    tf_dir = tmp_path / "tf"
    tf_dir.mkdir()
    _write_fake_guardrails(tf_dir)
    _write_fake_terraform(tmp_path)

    script = Path("scripts/release_hetzner.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), "plan"],
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "PATH": f"{tmp_path}:{os.environ.get('PATH', '')}",
            "TF_DIR": str(tf_dir),
            "HETZNER_API_TOKEN": "dummy",
            "TF_VAR_server_type": "cx23",
            "TF_VAR_node_count": "2",
            "TF_VAR_allow_scale": "true",
            "HETZNER_MONTHLY_INSTANCE_CAP": "1",
        },
        check=False,
    )
    assert result.returncode != 0
    assert "node_count" in result.stderr


def _write_tf_fixture(tf_dir: Path, *, backups: str = "false", extra_resource: str = "") -> None:
    tf_dir.mkdir(parents=True, exist_ok=True)
    (tf_dir / "main.tf").write_text(
        (
            'provider "hcloud" { token = "dummy" }\n'
            'resource "hcloud_firewall" "securewave" { name = "fw" }\n'
            f'resource "hcloud_server" "securewave" {{ name = "vpn-01" server_type = "cx33" image = "ubuntu-22.04" location = "ash" backups = {backups} }}\n'
            f"{extra_resource}\n"
        ),
        encoding="utf-8",
    )


def test_check_cost_guardrails_blocks_multi_server(tmp_path):
    tf_dir = tmp_path / "tf"
    _write_tf_fixture(tf_dir)
    tfvars = tf_dir / "terraform.tfvars"
    tfvars.write_text(
        'server_type = "cx33"\nnode_count = 2\nallow_scale = true\nssh_key_names=["dummy"]\n',
        encoding="utf-8",
    )

    script = Path("scripts/check_cost_guardrails.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), str(tfvars)],
        capture_output=True,
        text=True,
        env={**os.environ, "TF_DIR": str(tf_dir)},
        check=False,
    )
    assert result.returncode != 0
    assert "node_count" in result.stderr


def test_check_cost_guardrails_blocks_backups(tmp_path):
    tf_dir = tmp_path / "tf"
    _write_tf_fixture(tf_dir, backups="true")
    tfvars = tf_dir / "terraform.tfvars"
    tfvars.write_text(
        'server_type = "cx33"\nnode_count = 1\nallow_scale = false\nssh_key_names=["dummy"]\n',
        encoding="utf-8",
    )

    script = Path("scripts/check_cost_guardrails.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), str(tfvars)],
        capture_output=True,
        text=True,
        env={**os.environ, "TF_DIR": str(tf_dir)},
        check=False,
    )
    assert result.returncode != 0
    assert "backups" in result.stderr.lower()


def test_check_cost_guardrails_blocks_unexpected_resource(tmp_path):
    tf_dir = tmp_path / "tf"
    _write_tf_fixture(tf_dir, extra_resource='resource "hcloud_volume" "data" { name = "bad" size = 10 }\n')
    tfvars = tf_dir / "terraform.tfvars"
    tfvars.write_text(
        'server_type = "cx33"\nnode_count = 1\nallow_scale = false\nssh_key_names=["dummy"]\n',
        encoding="utf-8",
    )

    script = Path("scripts/check_cost_guardrails.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), str(tfvars)],
        capture_output=True,
        text=True,
        env={**os.environ, "TF_DIR": str(tf_dir)},
        check=False,
    )
    assert result.returncode != 0
    assert "Unexpected Hetzner resource type" in result.stderr


def test_check_cost_guardrails_passes_on_strict_single_server(tmp_path):
    tf_dir = tmp_path / "tf"
    _write_tf_fixture(tf_dir)
    tfvars = tf_dir / "terraform.tfvars"
    tfvars.write_text(
        'server_type = "cx23"\nnode_count = 1\nallow_scale = false\nssh_key_names=["dummy"]\n',
        encoding="utf-8",
    )

    script = Path("scripts/check_cost_guardrails.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), str(tfvars)],
        capture_output=True,
        text=True,
        env={**os.environ, "TF_DIR": str(tf_dir), "HETZNER_MONTHLY_INSTANCE_CAP": "1"},
        check=False,
    )
    assert result.returncode == 0
    assert "Cost guardrails OK" in result.stdout
