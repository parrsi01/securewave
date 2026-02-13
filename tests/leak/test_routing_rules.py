from dev_tools.sandbox.leak_tests.route_table_test import route_leak_detected


def test_routing_rules():
    leak, non_tunnel, has_tunnel = route_leak_detected(
        ["default dev wg0 scope link"],
        interface="wg0",
    )

    assert leak is False
    assert non_tunnel == []
    assert has_tunnel is True
