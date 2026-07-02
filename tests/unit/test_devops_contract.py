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


def test_ci_runs_on_active_os_branches_and_devops_gates():
    workflow = yaml.safe_load((ROOT / ".github/workflows/ci-cd.yml").read_text())
    push_branches = workflow[True]["push"]["branches"]
    pull_request_branches = workflow[True]["pull_request"]["branches"]
    jobs = workflow["jobs"]

    for branch in ("Linux", "Windows", "Mac"):
        assert branch in push_branches
        assert branch in pull_request_branches
    assert "flutter" not in push_branches
    assert "flutter" not in pull_request_branches
    assert "security-audit" in jobs
    assert "website-static" in jobs
    assert "flutter-android" in jobs


def test_release_workflows_cover_mobile_and_container_delivery():
    apple = yaml.safe_load((ROOT / ".github/workflows/apple-release.yml").read_text())
    container = yaml.safe_load((ROOT / ".github/workflows/container-release.yml").read_text())
    archive_script = (ROOT / "securewave_app/scripts/archive_ios_release.sh").read_text()

    assert "ios-unsigned" in apple["jobs"]
    assert "macos-ui-demo" in apple["jobs"]
    apple_steps = apple["jobs"]["ios-unsigned"]["steps"]
    macos_steps = apple["jobs"]["macos-ui-demo"]["steps"]
    assert any(step.get("name") == "Install Apple signing assets" for step in apple_steps)
    assert any(step.get("name") == "Collect unsigned iOS app artifact" for step in apple_steps)
    assert any("find securewave_app/build/ios -type d -name '*.app'" in str(step.get("run", "")) for step in apple_steps)
    assert any("apple-artifacts/ios-unsigned/securewave-ios-unsigned.zip" in str(step.get("with", "")) for step in apple_steps)
    assert any("securewave_app/scripts/archive_ios_release.sh" in str(step.get("run", "")) for step in apple_steps)
    assert any("securewave_app/scripts/package_macos_ui_demo.sh" in str(step.get("run", "")) for step in macos_steps)
    assert any(step.get("name") == "Publish macOS UI demo to branch" for step in macos_steps)
    assert "publish-image" in container["jobs"]
    assert container["permissions"]["packages"] == "write"
    build_step = container["jobs"]["publish-image"]["steps"][-1]
    assert build_step["uses"] == "docker/build-push-action@v6"
    assert "Runner.xcworkspace" in archive_script
    assert "xcodebuild archive" in archive_script
    assert "xcodebuild -exportArchive" in archive_script
    assert "APPLE_TEAM_ID" in archive_script


def test_apple_review_website_and_handoff_download_are_public():
    apple_page = (ROOT / "static/apple-review.html").read_text()
    downloads_page = (ROOT / "static/download.html").read_text()
    manifest = (ROOT / "static/downloads/manifest.json").read_text()
    handoff = (ROOT / "docs/APPLE_REVIEW_HANDOFF.md").read_text()
    macos_script = (ROOT / "securewave_app/scripts/package_macos_ui_demo.sh").read_text()

    assert "Packet Tunnel Provider" in apple_page
    assert "Hotspot Helper" in apple_page
    assert "/privacy.html" in apple_page
    assert "/contact.html" in apple_page
    assert "/apple-review.html" in downloads_page
    assert "securewave-apple-release-handoff.zip" in manifest
    assert "securewave-macos-arm64-ui-demo.zip" in manifest
    assert "package_macos_ui_demo.sh" in handoff
    assert "com.securewave.vpn.PacketTunnel" in handoff
    assert "vpn_not_configured" in macos_script


def test_demo_preflight_and_runbook_cover_live_tunnel_go_no_go():
    script = (ROOT / "scripts/demo_preflight.sh").read_text()
    proof = (ROOT / "scripts/linux_app_vpn_tunnel_proof.py").read_text()
    runbook = (ROOT / "docs/DEMO_RUNBOOK.md").read_text()

    assert "--live-go-no-go" in script
    assert "--require-email-health" in script
    assert "REQUIRE_REAL_TUNNEL=true" in script
    assert "REQUIRE_EMAIL_HEALTH=true" in script
    assert "check_helper_contract" in script
    assert "check_polkit_authorization" in script
    assert "check_real_tunnel_egress" in script
    assert "check_email_health" in script
    assert "/health/email" in script
    assert "https://api.ipify.org" in script
    assert 'getent ahosts "$host"' in script
    assert 'check_url "/downloads"' in script
    assert "prebuild_linux_bundle" in script
    assert "/auth/login" in script
    assert "/auth/register" not in script
    assert "disposable demo account" not in script
    assert "SECUREWAVE_TEST_EMAIL" in script
    assert "SECUREWAVE_CERT_AUTH_FILE" in script
    assert '"DEMO_EMAIL"' in proof
    assert '"DEMO_PASSWORD"' in proof
    assert "SECUREWAVE_CERT_AUTH_FILE" in proof
    assert "real tunnel" in runbook.lower()
    assert "fallback" in runbook.lower()
    assert "SECUREWAVE_SIMULATE_TUNNEL" in runbook
    assert "/vpn/servers?device_type=linux" in script
    assert "--revoke-devices" in script
    assert "flutter build linux --release" in script


def test_final_linux_gate_provisions_stable_account_without_churn_in_preflight():
    gate = (ROOT / "scripts/final_linux_demo_gate.sh").read_text()
    demo_preflight = (ROOT / "scripts/demo_preflight.sh").read_text()
    runtime_verifier = (ROOT / "scripts/linux_vpn_runtime_verifier.py").read_text()

    assert "--provision-live-account" in gate
    assert "--allow-active-tunnel" in gate
    assert "connected runtime snapshot" in gate
    assert "connected_transfer_proof" in gate
    assert "SECUREWAVE_TRANSFER_PROOF_BYTES" in gate
    assert "SECUREWAVE_TRANSFER_PROOF_URL" in gate
    assert "git_head=" in gate
    assert "--allow-active-tunnel" in runtime_verifier
    assert "SECUREWAVE_PROVISION_EMAIL" in gate
    assert "SECUREWAVE_PROVISION_PASSWORD" in gate
    assert "/auth/register" in gate
    assert "/auth/register" not in demo_preflight
    assert "securewave\\.ovpn" in demo_preflight


def test_email_release_gate_automates_private_env_preflight_and_live_proof():
    gate = (ROOT / "scripts/email_release_gate.sh").read_text()
    proof = (ROOT / "scripts/email_live_proof.py").read_text()
    report = (ROOT / "docs/DEVOPS_REPORT_SMTP_EMAIL_READINESS_2026-06-30.md").read_text()

    assert "securewave_private/release_email.env" in gate
    assert "scripts/release_preflight.sh" in gate
    assert "scripts/email_live_proof.py" in gate
    assert "--billing-env-file" in gate
    assert "securewave_private/billing_release.env" in gate
    assert "--generate-missing-keys" in gate
    assert "--dry-run-tag" in gate
    assert "getpass.getpass" in proof
    assert "/auth/verify-email" in proof
    assert "/auth/password-reset/request" in proof
    assert "/auth/password-reset/confirm" in proof
    assert "SECUREWAVE_EMAIL_PROOF_RESET_TOKEN" in proof
    assert "scripts/email_release_gate.sh" in report


def test_billing_release_gate_automates_private_stripe_env_validation():
    gate = (ROOT / "scripts/billing_release_gate.sh").read_text()
    provision = (ROOT / "scripts/stripe_billing_provision.py").read_text()
    provisioning_service = (ROOT / "services/stripe_provisioning.py").read_text()

    assert "securewave_private/billing_release.env" in gate
    assert "payment_config_issues" in gate
    assert "StripeService.config_status" in gate
    assert "STRIPE_SECRET_KEY" in gate
    assert "STRIPE_WEBHOOK_SECRET" in gate
    assert "STRIPE_PRICE_BASIC_MONTHLY" in gate
    assert "STRIPE_PORTAL_CONFIG_ID" in gate
    assert "--release-preflight" in gate
    assert "--release-env-file" in gate
    assert "securewave_private/release_email.env" in gate
    assert "scripts/release_preflight.sh" in gate
    assert "StripeBillingProvisioner" in provision
    assert "--confirm-live" in provision
    assert "checkout.session.completed" in provisioning_service
    assert "billing_portal.Configuration" in provisioning_service


def test_release_go_no_go_composes_private_email_and_billing_gates():
    gate = (ROOT / "scripts/release_go_no_go.sh").read_text()

    assert "securewave_private/release_email.env" in gate
    assert "securewave_private/billing_release.env" in gate
    assert "scripts/email_release_gate.sh" in gate
    assert "scripts/billing_release_gate.sh" in gate
    assert "scripts/release_preflight.sh" in gate
    assert "--email-live-proof" in gate
    assert "OK: composed release go/no-go checks passed." in gate
