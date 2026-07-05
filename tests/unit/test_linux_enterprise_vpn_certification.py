from scripts import linux_enterprise_vpn_certification as cert


def test_enterprise_certification_redacts_tokens_configs_and_emails():
    payload = {
        "email": "enterprise-cert@example.invalid",
        "access_token": "eyJabc.def.ghi",
        "wireguard_config": "[Interface]\nPrivateKey = secret\n[Peer]\n",
        "nested": {
            "ikev2_config": "connections { secret = nope }",
            "message": "contact enterprise-cert@example.invalid",
        },
    }

    redacted = cert.redact(payload)

    assert redacted["email"].startswith("sha256:")
    assert redacted["access_token"] == cert.REDACTED
    assert redacted["wireguard_config"] == cert.REDACTED
    assert redacted["nested"]["ikev2_config"] == cert.REDACTED
    assert "enterprise-cert@example.invalid" not in redacted["nested"]["message"]


def test_enterprise_readiness_matrix_requires_all_cohorts_and_protocol_profiles():
    simulation = {
        "ok": True,
        "cohorts": [
            {
                "cohort_size": 100,
                "ok": True,
                "users_completed": 100,
                "duration_seconds": 1.0,
                "protocol_profile_success": {
                    "wireguard": 100,
                    "openvpn": 100,
                    "ikev2": 100,
                },
                "database_integrity": {"usage_within_tolerance": True},
                "metrics": {
                    "endpoints": {
                        "auth.login": {"latency_ms": {"p95": 12.0}},
                        "vpn.profile.wireguard": {"latency_ms": {"p99": 15.0}},
                    },
                    "failures": [],
                },
            }
        ],
    }

    matrix = cert.readiness_matrix(simulation, live_proofs=None)

    assert matrix["overall"] == "ready_for_modeled_local_scale"
    assert matrix["enterprise_scale_readiness"]["100"]["status"] == "pass"
    assert matrix["protocol_readiness"]["wireguard"]["backend_profile_scale"] is True
    assert matrix["protocol_readiness"]["openvpn"]["backend_profile_scale"] is True
    assert matrix["protocol_readiness"]["ikev2"]["backend_profile_scale"] is True
    assert matrix["protocol_readiness"]["ikev2"]["live_runtime_proof"] == "not_run"


def test_enterprise_readiness_matrix_flags_missing_protocol_scale():
    simulation = {
        "ok": False,
        "cohorts": [
            {
                "cohort_size": 250,
                "ok": False,
                "users_completed": 250,
                "duration_seconds": 1.0,
                "protocol_profile_success": {
                    "wireguard": 250,
                    "openvpn": 249,
                    "ikev2": 250,
                },
                "database_integrity": {"usage_within_tolerance": True},
                "metrics": {"endpoints": {}, "failures": [{"check": "x"}]},
            }
        ],
    }

    matrix = cert.readiness_matrix(simulation, live_proofs={"ok": False, "results": []})

    assert matrix["overall"] == "not_ready"
    assert matrix["enterprise_scale_readiness"]["250"]["status"] == "fail"
    assert matrix["protocol_readiness"]["wireguard"]["backend_profile_scale"] is True
    assert matrix["protocol_readiness"]["openvpn"]["backend_profile_scale"] is False
