import os
import subprocess
from pathlib import Path

import pytest


GUARD = Path("securewave_app/scripts/authorize_linux_release.sh")
BUILD_DEB = Path("securewave_app/scripts/build_deb.sh")


def _candidate(tmp_path: Path) -> tuple[Path, str, Path]:
    repo = tmp_path / "candidate"
    repo.mkdir()
    subprocess.run(
        ["git", "init", "-q", "-b", "codex/linux-runtime-final"], cwd=repo, check=True
    )
    subprocess.run(
        ["git", "config", "user.email", "tests@example.invalid"], cwd=repo, check=True
    )
    subprocess.run(
        ["git", "config", "user.name", "SecureWave Tests"], cwd=repo, check=True
    )
    (repo / "tracked.txt").write_text("candidate\n", encoding="utf-8")
    subprocess.run(["git", "add", "tracked.txt"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "candidate"], cwd=repo, check=True)
    head = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repo, text=True
    ).strip()

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    uname = fake_bin / "uname"
    uname.write_text(
        "#!/usr/bin/env bash\n"
        'case "${1:-}" in\n'
        "  -s) printf '%s\\n' \"${FAKE_UNAME_S:-Linux}\" ;;\n"
        "  -m) printf '%s\\n' \"${FAKE_UNAME_M:-aarch64}\" ;;\n"
        "  *) exit 2 ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    uname.chmod(0o755)
    return repo, head, fake_bin


def _run_guard(tmp_path: Path, **overrides: str) -> subprocess.CompletedProcess[str]:
    repo, head, fake_bin = _candidate(tmp_path)
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fake_bin}:{env['PATH']}",
            "SECUREWAVE_PACKAGE_PROFILE": "production",
            "DEMO_MODE": "false",
            "WG_MOCK_MODE": "false",
            "SECUREWAVE_USE_MOCK_API": "false",
            "SECUREWAVE_API_BASE_URL": "https://api.example.test/api",
            "SECUREWAVE_RELEASE_CANDIDATE_SHA": head,
            "SECUREWAVE_RELEASE_AUTHORIZATION": (
                f"approve:codex/linux-runtime-final:{head}"
            ),
        }
    )
    env.update(overrides)
    return subprocess.run(
        ["bash", str(GUARD.resolve()), str(repo)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def test_release_guard_accepts_exact_authorized_candidate(tmp_path: Path):
    result = _run_guard(tmp_path)

    assert result.returncode == 0, result.stderr
    assert "release source authorized" in result.stdout


@pytest.mark.parametrize(
    ("overrides", "message"),
    (
        ({"SECUREWAVE_RELEASE_AUTHORIZATION": ""}, "authorization is required"),
        ({"SECUREWAVE_RELEASE_AUTHORIZATION": "approved"}, "malformed or mismatched"),
        ({"SECUREWAVE_RELEASE_CANDIDATE_SHA": "bad"}, "missing or malformed"),
        ({"SECUREWAVE_RELEASE_CANDIDATE_SHA": "0" * 40}, "does not match HEAD"),
        ({"SECUREWAVE_PACKAGE_PROFILE": "debug"}, "production package profile"),
        ({"SECUREWAVE_API_BASE_URL": "http://api.example.test/api"}, "must use HTTPS"),
        (
            {"SECUREWAVE_API_BASE_URL": "https://api.example.test/v1/api"},
            "approved /api path",
        ),
        ({"SECUREWAVE_API_BASE_URL": "https://127.0.0.1/api"}, "must not be local"),
        ({"SECUREWAVE_USE_MOCK_API": "true"}, "must be explicitly false"),
        ({"DEMO_MODE": "true"}, "must be explicitly false"),
        ({"WG_MOCK_MODE": "true"}, "must be explicitly false"),
        ({"FAKE_UNAME_S": "Darwin"}, "Linux is required"),
        ({"FAKE_UNAME_M": "x86_64"}, "ARM64 is required"),
    ),
)
def test_release_guard_rejects_unauthorized_sources(
    tmp_path: Path, overrides: dict[str, str], message: str
):
    result = _run_guard(tmp_path, **overrides)

    assert result.returncode != 0
    assert message in result.stderr


def test_release_guard_rejects_wrong_branch_and_dirty_tree(tmp_path: Path):
    repo, head, fake_bin = _candidate(tmp_path)
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fake_bin}:{env['PATH']}",
            "SECUREWAVE_PACKAGE_PROFILE": "production",
            "DEMO_MODE": "false",
            "WG_MOCK_MODE": "false",
            "SECUREWAVE_USE_MOCK_API": "false",
            "SECUREWAVE_API_BASE_URL": "https://api.example.test/api",
            "SECUREWAVE_RELEASE_CANDIDATE_SHA": head,
            "SECUREWAVE_RELEASE_AUTHORIZATION": (
                f"approve:codex/linux-runtime-final:{head}"
            ),
        }
    )

    subprocess.run(["git", "switch", "-q", "-c", "other"], cwd=repo, check=True)
    wrong_branch = subprocess.run(
        ["bash", str(GUARD.resolve()), str(repo)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert wrong_branch.returncode != 0
    assert "authorized release branch" in wrong_branch.stderr

    subprocess.run(
        ["git", "switch", "-q", "codex/linux-runtime-final"], cwd=repo, check=True
    )
    (repo / "untracked.txt").write_text("dirty\n", encoding="utf-8")
    dirty = subprocess.run(
        ["bash", str(GUARD.resolve()), str(repo)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert dirty.returncode != 0
    assert "worktree is not clean" in dirty.stderr


def test_package_path_is_guarded_and_embeds_release_provenance():
    build = BUILD_DEB.read_text(encoding="utf-8")

    assert '"$ROOT_DIR/scripts/authorize_linux_release.sh" "$REPO_DIR"' in build
    assert build.index("authorize_linux_release.sh") < build.index("flutter pub get")
    assert '--dart-define="SECUREWAVE_API_BASE_URL=$SECUREWAVE_API_BASE_URL"' in build
    assert "--dart-define=SECUREWAVE_USE_MOCK_API=false" in build
    for marker in (
        "source-sha",
        "source-tree-state",
        "app-version",
        "package-architecture",
        "helper-contract",
    ):
        assert f"usr/share/securewave/release/{marker}" in build


def test_release_guard_does_not_echo_rejected_input(tmp_path: Path):
    marker = "must-not-appear-in-logs"
    result = _run_guard(
        tmp_path,
        SECUREWAVE_API_BASE_URL=f"https://user:{marker}@api.example.test/api",
    )

    assert result.returncode != 0
    assert marker not in result.stdout
    assert marker not in result.stderr
