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


def test_release_workflows_cover_mobile_and_container_delivery():
    apple = yaml.safe_load((ROOT / ".github/workflows/apple-release.yml").read_text())
    container = yaml.safe_load((ROOT / ".github/workflows/container-release.yml").read_text())

    assert "ios-unsigned" in apple["jobs"]
    assert "publish-image" in container["jobs"]
    assert container["permissions"]["packages"] == "write"
    build_step = container["jobs"]["publish-image"]["steps"][-1]
    assert build_step["uses"] == "docker/build-push-action@v6"


def test_demo_preflight_and_runbook_cover_live_tunnel_go_no_go():
    script = (ROOT / "scripts/demo_preflight.sh").read_text()
    runbook = (ROOT / "docs/DEMO_RUNBOOK.md").read_text()

    assert "--live-go-no-go" in script
    assert "check_polkit_authorization" in script
    assert "check_real_tunnel_egress" in script
    assert "real tunnel" in runbook.lower()
    assert "fallback" in runbook.lower()
    assert "SECUREWAVE_SIMULATE_TUNNEL" in runbook
    assert "/vpn/servers?device_type=linux" in script
    assert "--revoke-devices" in script
    assert "flutter build linux --release" in script
