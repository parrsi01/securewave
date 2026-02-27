from routes.vpn import (
    _classify_protocol_provision_error,
    _provisioning_failure_should_block,
)


def test_classify_protocol_provision_error_misconfigured():
    code = _classify_protocol_provision_error(
        "openvpn",
        "OpenVPN provisioning response missing ovpn_config_b64",
    )
    assert code == "openvpn_server_misconfigured"


def test_classify_protocol_provision_error_healthcheck():
    code = _classify_protocol_provision_error(
        "ikev2",
        "ssh: connect timeout to host",
    )
    assert code == "ikev2_healthcheck_fail"


def test_classify_protocol_provision_error_fallback():
    code = _classify_protocol_provision_error("openvpn", "unexpected failure")
    assert code == "credential_provision_failed"


def test_provisioning_failure_block_policy():
    assert _provisioning_failure_should_block("Auto provisioning disabled") is False
    assert _provisioning_failure_should_block("not_applicable") is False
    assert _provisioning_failure_should_block("credential_provision_failed") is True
