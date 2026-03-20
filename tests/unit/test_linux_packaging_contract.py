from pathlib import Path


def test_linux_runner_and_packaging_share_helper_contract():
    runner = Path("securewave_app/linux/runner/my_application.cc").read_text(
        encoding="utf-8"
    )
    script = Path("securewave_app/scripts/build_deb.sh").read_text(
        encoding="utf-8"
    )
    helper = Path("securewave_app/packaging/linux/securewave-wg-quick").read_text(
        encoding="utf-8"
    )
    contract = Path(
        "securewave_app/packaging/linux/securewave-wg-quick.contract"
    ).read_text(encoding="utf-8")
    polkit = Path(
        "securewave_app/packaging/linux/50-securewave-wg.rules"
    ).read_text(encoding="utf-8")

    assert (
        'const char* kSecureWaveWgHelperContractPath =\n'
        '    "/usr/local/libexec/securewave-wg-quick.contract";'
    ) in runner
    assert (
        'const char* kSecureWavePolkitRulePath =\n'
        '    "/etc/polkit-1/rules.d/50-securewave-wg.rules";'
    ) in runner
    assert 'const char* kSecureWaveWgHelperContractVersion = "2";' in runner

    assert 'HELPER_CONTRACT=$HELPER_DIR/securewave-wg-quick.contract' in script
    assert 'SOURCE_CONTRACT=$SOURCE_DIR/securewave-wg-quick.contract' in script
    assert 'install -m 0755 "$SOURCE_HELPER" "$HELPER"' in script
    assert 'install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"' in script
    assert 'rm -f /usr/local/libexec/securewave-wg-quick.contract' in script
    assert "policy-ensure|policy-clear|policy-clear-link|nm-unmanaged|nm-reset" in helper
    assert contract.strip() == "2"
    assert '/usr/local/libexec/securewave-wg-quick' in polkit
