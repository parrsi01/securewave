from __future__ import annotations

import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)


def test_generate_release_readiness_report_pass(tmp_path: Path) -> None:
    verify = tmp_path / "verify.sh"
    sync = tmp_path / "sync.sh"
    audit = tmp_path / "audit.sh"
    workflow = tmp_path / "workflow.yml"
    out = tmp_path / "report.md"

    _write_exec(verify, "#!/usr/bin/env bash\nset -euo pipefail\necho 'Verification mode: strict'\necho 'Errors: 0'\n")
    _write_exec(sync, "#!/usr/bin/env bash\nset -euo pipefail\necho 'OK: dry-run completed.'\n")
    _write_exec(audit, "#!/usr/bin/env bash\nset -euo pipefail\necho 'OK: all required release secrets are present.'\n")
    workflow.write_text("name: test\n", encoding="utf-8")

    env = os.environ.copy()
    env["VERIFY_PRODUCTION_ENV_SCRIPT"] = str(verify)
    env["SYNC_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(sync)
    env["AUDIT_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(audit)
    env["RELEASE_WORKFLOW_FILE"] = str(workflow)
    env["GITHUB_REPOSITORY"] = "parrsi01/securewave"

    result = subprocess.run(
        ["/bin/bash", "scripts/generate_release_readiness_report.sh", "--output", str(out)],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    content = out.read_text(encoding="utf-8")
    assert "Local env readiness: **PASS**" in content
    assert "Workflow dispatch readiness: **PASS**" in content
    assert "- None" in content


def test_generate_release_readiness_report_fail_lists_blockers(tmp_path: Path) -> None:
    verify = tmp_path / "verify.sh"
    sync = tmp_path / "sync.sh"
    audit = tmp_path / "audit.sh"
    workflow = tmp_path / "workflow.yml"
    out = tmp_path / "report.md"

    _write_exec(
        verify,
        "#!/usr/bin/env bash\nset -euo pipefail\necho 'ERROR: DATABASE_URL is required.'\nexit 1\n",
    )
    _write_exec(
        sync,
        "#!/usr/bin/env bash\nset -euo pipefail\necho 'Local environment is missing required values for:'\necho ' - SMTP_HOST'\nexit 1\n",
    )
    _write_exec(
        audit,
        "#!/usr/bin/env bash\nset -euo pipefail\necho 'Missing required release secrets:'\necho ' - STRIPE_SECRET_KEY'\nexit 1\n",
    )
    workflow.write_text("name: test\n", encoding="utf-8")

    env = os.environ.copy()
    env["VERIFY_PRODUCTION_ENV_SCRIPT"] = str(verify)
    env["SYNC_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(sync)
    env["AUDIT_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(audit)
    env["RELEASE_WORKFLOW_FILE"] = str(workflow)
    env["GITHUB_REPOSITORY"] = "parrsi01/securewave"

    result = subprocess.run(
        ["/bin/bash", "scripts/generate_release_readiness_report.sh", "--output", str(out)],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    content = out.read_text(encoding="utf-8")
    assert "Local env readiness: **FAIL**" in content
    assert "GitHub secret sync readiness: **FAIL**" in content
    assert "GitHub secret inventory readiness: **FAIL**" in content
    assert "Workflow dispatch readiness: **FAIL**" in content
    assert "- ERROR: DATABASE_URL is required." in content
    assert "-  - SMTP_HOST" not in content
    assert "- SMTP_HOST" in content
    assert "- STRIPE_SECRET_KEY" in content
