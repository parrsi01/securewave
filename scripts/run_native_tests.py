#!/usr/bin/env python3
"""Build/run isolated helper tests without touching the installed daemon."""
import pathlib
import shlex
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "glib-2.0", "gio-2.0"], text=True))
    with tempfile.TemporaryDirectory(prefix="securewave-native-test-") as directory:
        binary = str(pathlib.Path(directory) / "helper-test")
        subprocess.run(["g++", "-std=c++14", str(ROOT / "securewave_app/linux/tests/securewave_helperd_test.cc"),
                        "-o", binary, *flags], check=True)
        subprocess.run([binary], check=True)
        subprocess.run(["bash", str(ROOT / "securewave_app/linux/tests/wg_quick_peer_query_test.sh"),
                        str(ROOT / "securewave_app/packaging/linux/securewave-wg-quick")], check=True)
    print("Native helper and wrapper checks passed.")


if __name__ == "__main__":
    main()
