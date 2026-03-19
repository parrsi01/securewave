from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


def _build_minimal_deb(base: Path, *, include_helper_paths: bool = True) -> Path:
    staging = base / "pkg"
    control = staging / "DEBIAN"
    securewave_dir = staging / "usr/lib/securewave"
    bin_dir = staging / "usr/bin"
    desktop_dir = staging / "usr/share/applications"
    control.mkdir(parents=True)
    securewave_dir.mkdir(parents=True)
    bin_dir.mkdir(parents=True)
    desktop_dir.mkdir(parents=True)

    (control / "control").write_text(
        "\n".join(
            [
                "Package: securewave-vpn",
                "Version: 4.0.0",
                "Section: net",
                "Priority: optional",
                "Architecture: arm64",
                "Depends: wireguard-tools, policykit-1",
                "Maintainer: Test <test@example.com>",
                "Description: SecureWave VPN desktop client",
                "",
            ]
        ),
        encoding="utf-8",
    )

    postinst_lines = [
        "#!/bin/bash",
        "set -e",
    ]
    if include_helper_paths:
        postinst_lines.extend(
            [
                "echo /usr/local/libexec/securewave-wg-quick >/dev/null",
                "echo /usr/local/libexec/securewave-wg-quick.contract >/dev/null",
                "echo /etc/polkit-1/rules.d/50-securewave-wg.rules >/dev/null",
            ]
        )
    (control / "postinst").write_text("\n".join(postinst_lines) + "\n", encoding="utf-8")
    (control / "postinst").chmod(0o755)

    (control / "postrm").write_text(
        "\n".join(
            [
                "#!/bin/bash",
                "set -e",
                "rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules",
                "rm -f /usr/local/libexec/securewave-wg-quick.contract",
                "rm -f /usr/local/libexec/securewave-wg-quick",
                "",
            ]
        ),
        encoding="utf-8",
    )
    (control / "postrm").chmod(0o755)

    (securewave_dir / "securewave_app").write_text("binary", encoding="utf-8")
    (bin_dir / "securewave-vpn").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
    (desktop_dir / "securewave-vpn.desktop").write_text("[Desktop Entry]\n", encoding="utf-8")

    output = base / "securewave-vpn_4.0.0_arm64.deb"
    subprocess.run(
        ["dpkg-deb", "--build", "--root-owner-group", str(staging), str(output)],
        check=True,
        capture_output=True,
        text=True,
    )
    return output


def test_verify_linux_package_artifact_passes_for_expected_package(tmp_path):
    if shutil.which("dpkg-deb") is None:
        raise AssertionError("dpkg-deb is required for this test")

    package_path = _build_minimal_deb(tmp_path)
    script = Path("securewave_app/scripts/verify_linux_package_artifact.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), str(package_path)],
        capture_output=True,
        text=True,
        env=os.environ,
        check=False,
    )

    assert result.returncode == 0
    assert "OK: verified Linux package artifact" in result.stdout


def test_verify_linux_package_artifact_rejects_missing_helper_install(tmp_path):
    if shutil.which("dpkg-deb") is None:
        raise AssertionError("dpkg-deb is required for this test")

    package_path = _build_minimal_deb(tmp_path, include_helper_paths=False)
    script = Path("securewave_app/scripts/verify_linux_package_artifact.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), str(package_path)],
        capture_output=True,
        text=True,
        env=os.environ,
        check=False,
    )

    assert result.returncode != 0
    assert "missing helper install path" in result.stderr
