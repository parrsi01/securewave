#!/usr/bin/env python3
"""Validate live-certification inputs locally without contacting an API."""

from __future__ import annotations

import argparse
import os
import sys
import urllib.parse

try:
    from scripts import linux_app_vpn_tunnel_proof as certification
except ModuleNotFoundError:  # Direct execution from scripts/.
    import linux_app_vpn_tunnel_proof as certification


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--api-base",
        default=os.environ.get("SECUREWAVE_API_BASE_URL"),
        help="Explicit authorized staging API base.",
    )
    parser.add_argument(
        "--auth-file",
        default=os.environ.get("SECUREWAVE_CERT_AUTH_FILE"),
        help="Protected auth file for one existing stable account.",
    )
    parser.add_argument("--allow-production", action="store_true")
    args = parser.parse_args(argv)

    try:
        api_base = certification._canonical_api_base(
            args.api_base or "", allow_production=args.allow_production
        )
    except argparse.ArgumentTypeError as error:
        parser.error(str(error))

    auth_path = certification._credential_file_path(args.auth_file)
    if auth_path is None or not auth_path.is_file():
        parser.error("a protected stable-account auth file is required")
    security_error = certification._credential_file_security_error(auth_path)
    if security_error:
        parser.error(security_error)
    values = certification._parse_env_file(auth_path)
    email = certification._file_default(
        values,
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
        "SECUREWAVE_TEST_EMAIL",
        "DEMO_EMAIL",
    )
    password = certification._file_default(
        values,
        "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
        "SECUREWAVE_TEST_PASSWORD",
        "DEMO_PASSWORD",
    )
    credential_error = certification._credential_error(email, password)
    if credential_error:
        parser.error(credential_error)

    host = (urllib.parse.urlsplit(api_base).hostname or "").lower()
    target_kind = "loopback" if host in {"localhost", "127.0.0.1", "::1"} else "staging"
    if host == "api.securewaveapp.com":
        target_kind = "production-explicitly-authorized"
    print("auth_file=ready")
    print("stable_account=ready")
    print(f"api_target={target_kind}")
    print("protocol=wireguard")
    return 0


if __name__ == "__main__":
    sys.exit(main())
