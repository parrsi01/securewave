from pathlib import Path


def test_linux_runner_and_packaging_share_helper_contract():
    runner = Path("securewave_app/linux/runner/my_application.cc").read_text(
        encoding="utf-8"
    )
    script = Path("securewave_app/scripts/build_deb.sh").read_text(
        encoding="utf-8"
    )

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
    assert 'HELPER_CONTRACT_VERSION=2' in script
    assert "printf '%s\\n' \"$HELPER_CONTRACT_VERSION\" > \"$HELPER_CONTRACT\"" in script
    assert 'rm -f /usr/local/libexec/securewave-wg-quick.contract' in script
