from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]


def test_dockerfile_copies_runtime_import_packages():
    dockerfile = (ROOT / "Dockerfile").read_text()
    required_entries = [
        "COPY background_tasks.py .",
        "COPY config/ ./config/",
        "COPY database/ ./database/",
        "COPY infrastructure/ ./infrastructure/",
        "COPY ml/ ./ml/",
        "COPY models/ ./models/",
        "COPY routers/ ./routers/",
        "COPY routes/ ./routes/",
        "COPY services/ ./services/",
        "COPY utils/ ./utils/",
    ]

    for entry in required_entries:
        assert entry in dockerfile


def test_ci_runs_on_active_flutter_branch_and_devops_gates():
    workflow = yaml.safe_load((ROOT / ".github/workflows/ci-cd.yml").read_text())
    push_branches = workflow[True]["push"]["branches"]
    pull_request_branches = workflow[True]["pull_request"]["branches"]
    jobs = workflow["jobs"]

    assert "flutter" in push_branches
    assert "flutter" in pull_request_branches
    assert "security-audit" in jobs
    assert "website-static" in jobs
    assert "flutter-android" in jobs
