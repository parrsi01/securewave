from sandbox.leak_tests.dns_leak_test import evaluate_dns_servers, parse_nameservers


def test_dns_no_leak():
    nameservers = parse_nameservers("""
    nameserver 94.140.14.14
    nameserver 10.8.0.1
    """)
    is_clean, leaked = evaluate_dns_servers(
        nameservers,
        allowed={"94.140.14.14", "94.140.15.15"},
        allow_private=True,
    )

    assert is_clean is True
    assert leaked == []
