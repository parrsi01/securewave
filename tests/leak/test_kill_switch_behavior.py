from dev_tools.sandbox.leak_tests.interface_flap_test import evaluate_kill_switch


def test_kill_switch_behavior():
    result = evaluate_kill_switch(
        down_routes=[],
        up_routes=["default dev wg0 scope link"],
        interface="wg0",
    )

    assert result["down_ok"] is True
    assert result["up_ok"] is True
    assert result["down_non_tunnel"] == []
    assert result["up_non_tunnel"] == []
