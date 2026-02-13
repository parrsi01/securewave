from dev_tools.sandbox.leak_tests.ipv6_leak_test import classify_ipv6_state


def test_ipv6_blocking():
    status, detail = classify_ipv6_state(
        disabled_value="1",
        routes=[],
        interface="wg0",
        iface_present=True,
        strict_live=True,
    )

    assert status == "ok"
    assert detail == "ipv6_disabled"
