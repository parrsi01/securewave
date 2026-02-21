import subprocess
from pathlib import Path


def test_multiprotocol_ci_safety_script_passes() -> None:
    root = Path(__file__).resolve().parents[2]
    script = root / "scripts" / "ci_multiprotocol_safety_check.sh"
    result = subprocess.run(["bash", str(script)], cwd=root, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + "\n" + result.stderr
    assert "ci_multiprotocol_safety_check:ok" in result.stdout
