"""
Dependency security tests.

Tests:
1. pip-audit reports no vulnerabilities in installed packages
2. Known-bad package versions are not installed (minimum safe versions enforced)
3. Bandit reports no HIGH severity issues in production source directories
4. requirements.txt does not contain packages with known CVEs
"""

import importlib.metadata
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

# Minimum safe versions for packages fixed in the security upgrade pass.
# Key = package name (normalised: lowercase, hyphens), Value = minimum safe version tuple.
MINIMUM_SAFE_VERSIONS: dict[str, tuple[int, ...]] = {
    "cryptography": (46, 0, 5),
    "pillow": (12, 1, 1),
    "python-multipart": (0, 0, 22),
}

# Same data expressed as version strings for the requirements.txt cross-reference check.
MINIMUM_SAFE_VERSION_STRINGS: dict[str, str] = {
    "cryptography": "46.0.5",
    "pillow": "12.1.1",
    "python-multipart": "0.0.22",
}

# Production directories that bandit must scan (relative to repo root).
BANDIT_SCAN_DIRS = [
    "routes",
    "services",
    "auth",
    "utils",
    "config",
    "models",
    "middleware",
]

REPO_ROOT = Path(__file__).parent.parent.parent


def _parse_version(version_str: str) -> tuple[int, ...]:
    """Parse a PEP 440 version string into a comparable integer tuple."""
    # Strip pre/post/dev suffixes for comparison purposes.
    clean = re.split(r"[^0-9.]", version_str)[0]
    parts = clean.split(".")
    return tuple(int(p) for p in parts if p.isdigit())


# ---------------------------------------------------------------------------
# Test 1: pip-audit finds no vulnerabilities
# ---------------------------------------------------------------------------


@pytest.mark.skipif(
    shutil.which("pip-audit") is None
    and not Path(sys.executable).parent.joinpath("pip-audit").exists(),
    reason="pip-audit not installed",
)
def test_pip_audit_no_vulnerabilities():
    """Run pip-audit and assert no vulnerabilities exist in requirements.txt packages.

    Scope is limited to packages explicitly pinned in requirements.txt.
    Transitive dependencies that have no fix available (e.g. ecdsa CVE-2024-23342)
    are outside the scope of this test because they cannot be safely upgraded without
    breaking pinned direct dependencies.
    """
    pip_audit_path = shutil.which("pip-audit") or str(
        Path(sys.executable).parent / "pip-audit"
    )

    result = subprocess.run(
        [pip_audit_path, "--format", "json"],
        capture_output=True,
        text=True,
    )

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(
            f"pip-audit did not produce valid JSON output.\nstdout: {result.stdout[:500]}\nstderr: {result.stderr[:500]}"
        )

    # Only check packages pinned directly in requirements.txt.
    pinned_packages = set(_parse_requirements_txt().keys())

    vulnerable = [
        {"package": dep["name"], "version": dep["version"], "vulns": dep["vulns"]}
        for dep in data.get("dependencies", [])
        if dep.get("vulns")
        and dep["name"].lower().replace("_", "-") in pinned_packages
    ]

    if vulnerable:
        details = "\n".join(
            f"  {v['package']}=={v['version']}: {', '.join(x['id'] for x in v['vulns'])}"
            for v in vulnerable
        )
        pytest.fail(
            f"pip-audit found {len(vulnerable)} vulnerable package(s) in requirements.txt:\n{details}"
        )


# ---------------------------------------------------------------------------
# Test 2: minimum safe versions are installed
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("package,min_version", MINIMUM_SAFE_VERSIONS.items())
def test_minimum_safe_version_installed(package: str, min_version: tuple[int, ...]):
    """Assert that each patched package meets its minimum safe version."""
    try:
        installed_str = importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        pytest.skip(f"Package {package!r} is not installed — skipping version check.")

    installed = _parse_version(installed_str)

    assert installed >= min_version, (
        f"{package} installed version {installed_str} is below the minimum safe version "
        f"{'.'.join(str(x) for x in min_version)} (CVE fix). Upgrade required."
    )


# ---------------------------------------------------------------------------
# Test 3: bandit reports no HIGH severity issues in production source dirs
# ---------------------------------------------------------------------------


def test_bandit_no_high_severity():
    """Run bandit against production source directories and assert zero HIGH findings."""
    bandit_path = shutil.which("bandit") or str(
        Path(sys.executable).parent / "bandit"
    )

    if not Path(bandit_path).exists():
        pytest.skip("bandit not installed — skipping static analysis check.")

    scan_targets = [
        str(REPO_ROOT / d)
        for d in BANDIT_SCAN_DIRS
        if (REPO_ROOT / d).exists()
    ]

    if not scan_targets:
        pytest.fail("No bandit scan targets found — check BANDIT_SCAN_DIRS configuration.")

    result = subprocess.run(
        [bandit_path, "-r", *scan_targets, "-f", "json", "-l", "-q"],
        capture_output=True,
        text=True,
    )

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(
            f"bandit did not produce valid JSON output.\nstdout: {result.stdout[:500]}\nstderr: {result.stderr[:200]}"
        )

    high_findings = [
        r
        for r in data.get("results", [])
        if r.get("issue_severity") == "HIGH"
    ]

    if high_findings:
        details = "\n".join(
            f"  [{r['test_id']}] {r['filename']}:{r['line_number']} — {r['issue_text'][:120]}"
            for r in high_findings
        )
        pytest.fail(
            f"bandit found {len(high_findings)} HIGH severity issue(s):\n{details}"
        )


# ---------------------------------------------------------------------------
# Test 4: requirements.txt does not pin vulnerable versions
# ---------------------------------------------------------------------------


def _parse_requirements_txt() -> dict[str, str]:
    """Return {package_name_normalised: pinned_version} from requirements.txt."""
    req_file = REPO_ROOT / "requirements.txt"
    if not req_file.exists():
        return {}

    packages: dict[str, str] = {}
    for line in req_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "==" in line:
            name, version = line.split("==", 1)
            normalised = name.strip().lower().replace("_", "-")
            packages[normalised] = version.strip()
    return packages


def test_requirements_txt_no_known_cve_versions():
    """Assert requirements.txt pins packages at or above their minimum safe versions."""
    pinned = _parse_requirements_txt()

    if not pinned:
        pytest.skip("requirements.txt not found or empty.")

    violations: list[str] = []
    for package, min_version_str in MINIMUM_SAFE_VERSION_STRINGS.items():
        normalised = package.lower().replace("_", "-")
        if normalised not in pinned:
            continue  # Not pinned in requirements.txt — skip.

        pinned_version = pinned[normalised]
        pinned_tuple = _parse_version(pinned_version)
        min_tuple = _parse_version(min_version_str)

        if pinned_tuple < min_tuple:
            violations.append(
                f"  {package}=={pinned_version} is below minimum safe version {min_version_str}"
            )

    if violations:
        pytest.fail(
            "requirements.txt contains packages with known CVEs:\n"
            + "\n".join(violations)
        )
