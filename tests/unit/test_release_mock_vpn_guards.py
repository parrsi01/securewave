import os
import subprocess
from pathlib import Path


def _write_shim(path: Path, name: str) -> None:
    script = path / name
    script.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    script.chmod(0o755)


def test_build_deb_refuses_mock_vpn_release_env(tmp_path):
    shim_dir = tmp_path / "shim"
    shim_dir.mkdir()
    for tool in ("wg-quick", "flutter", "dpkg-deb"):
      _write_shim(shim_dir, tool)

    script = Path("securewave_app/scripts/build_deb.sh")
    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "PATH": f"{shim_dir}:{os.environ.get('PATH', '')}",
            "SECUREWAVE_MOCK_VPN": "true",
        },
        check=False,
    )

    assert result.returncode != 0
    assert "refusing release build with mock VPN settings enabled" in result.stderr


def test_build_appimage_refuses_mock_vpn_release_env(tmp_path):
    shim_dir = tmp_path / "shim"
    shim_dir.mkdir()
    for tool in ("wg-quick", "flutter", "appimage-builder"):
      _write_shim(shim_dir, tool)

    script = Path("securewave_app/scripts/build_appimage.sh")
    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "PATH": f"{shim_dir}:{os.environ.get('PATH', '')}",
            "SECUREWAVE_MOCK_VPN_UNSTABLE": "true",
        },
        check=False,
    )

    assert result.returncode != 0
    assert "refusing release build with mock VPN settings enabled" in result.stderr
