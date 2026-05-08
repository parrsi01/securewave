from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_MULTIPART_PIN = "python-multipart==0.0.27"
RUNTIME_REQUIREMENT_FILES = (
    "requirements.txt",
    "requirements_production.txt",
    "requirements_minimal.txt",
)


def _requirement_lines(filename: str) -> list[str]:
    return [
        line.strip()
        for line in (REPO_ROOT / filename).read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def test_python_multipart_pin_is_patched_in_runtime_requirement_files() -> None:
    for filename in RUNTIME_REQUIREMENT_FILES:
        lines = _requirement_lines(filename)
        assert PYTHON_MULTIPART_PIN in lines
        assert not any(
            line.startswith("python-multipart==") and line != PYTHON_MULTIPART_PIN
            for line in lines
        )
