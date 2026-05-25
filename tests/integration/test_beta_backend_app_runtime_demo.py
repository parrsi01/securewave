from scripts.beta_backend_app_runtime_demo import PROTOCOLS, run_demo


def test_beta_backend_app_runtime_demo_executes_all_app_vpn_backend_paths():
    summary = run_demo(
        email="beta-demo-test@gmail.com",
        password="BetaSmoke123!A1",
    )

    assert summary["ok"] is True
    assert summary["account_email"] == "beta-demo-test@gmail.com"
    assert summary["plan"] == "Free"
    assert summary["usage"]["limit_gb"] == 5.0
    assert set(summary["protocols_enabled"]) == set(PROTOCOLS)

    for protocol in PROTOCOLS:
        assert summary["profile_statuses"][protocol] == 200
        assert summary["profile_shapes"][protocol]["runnable_config"] is True
