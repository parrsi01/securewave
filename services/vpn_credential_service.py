from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import shlex
import subprocess
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.orm import Session

from config.settings import get_settings
from models.vpn_credential import VPNCredential
from services.wireguard_server_manager import get_wireguard_server_manager, server_connection_from_db
from utils.env_validation import validate_fernet_key, is_production

logger = logging.getLogger(__name__)
_REMOTE_EXIT_MARKER = "__SECUREWAVE_REMOTE_EXIT_CODE__="
_REMOTE_OUTPUT_LIMIT = 8192


@dataclass(frozen=True)
class VpnProtocolCredentials:
    username: str
    password: str
    created: bool


@dataclass(frozen=True)
class ProvisionedOpenVpnProfile:
    credential_id: int
    revision: int
    common_name: str
    ovpn_config: str
    cert_serial: Optional[str]
    cert_fingerprint_sha256: Optional[str]
    expires_at: Optional[datetime]
    provisioned_on_server: bool
    status_message: str


@dataclass(frozen=True)
class ProvisionedIkev2Profile:
    credential_id: int
    revision: int
    common_name: str
    server: str
    remote_id: Optional[str]
    ca_cert_pem: Optional[str]
    client_pkcs12_base64: str
    client_pkcs12_password: str
    cert_serial: Optional[str]
    cert_fingerprint_sha256: Optional[str]
    expires_at: Optional[datetime]
    provisioned_on_server: bool
    status_message: str


@dataclass(frozen=True)
class RemoteScriptExecution:
    ok: bool
    stdout: str
    stderr: str
    exit_code: Optional[int]
    duration_ms: int
    command_summary: str


class RemoteScriptError(RuntimeError):
    def __init__(
        self,
        context: str,
        *,
        exit_code: Optional[int],
        duration_ms: int,
        command_summary: str,
        filtered_stderr: str,
        stdout: str,
    ):
        self.exit_code = exit_code
        self.duration_ms = duration_ms
        self.command_summary = command_summary
        self.filtered_stderr = filtered_stderr
        self.stdout_excerpt = VpnCredentialService._truncate_diagnostic_output(stdout)

        parts = [
            context,
            f"exit_code={exit_code if exit_code is not None else 'transport_error'}",
            f"duration_ms={duration_ms}",
            f"command={command_summary}",
        ]
        if self.filtered_stderr:
            parts.append(f"stderr={self.filtered_stderr}")
        if self.stdout_excerpt:
            parts.append(f"stdout={self.stdout_excerpt}")
        super().__init__(" | ".join(parts))


class VpnCredentialService:
    """
    Manage per-device VPN credentials.

    Supported modes:
    - openvpn/ikev2 username+password (legacy fallback)
    - openvpn mTLS certificates
    - ikev2 EAP-TLS certificates

    Private profile material is never persisted in plaintext; certificate private
    keys remain server-side until handed directly to the requesting client.
    """

    def __init__(self, db: Session):
        self.db = db
        self.fernet = self._load_fernet()
        self.testing = self._parse_bool_env("TESTING", get_settings().testing)

    def _load_fernet(self) -> Optional[Fernet]:
        key = (os.getenv("AUTH_ENCRYPTION_KEY") or os.getenv("WG_ENCRYPTION_KEY") or "").strip()
        issue = validate_fernet_key(key)
        if issue:
            if is_production():
                raise RuntimeError(f"AUTH_ENCRYPTION_KEY/WG_ENCRYPTION_KEY {issue} in production")
            logger.warning("Credential encryption key %s; using base64 fallback", issue)
            return None
        return Fernet(key.encode())

    def _encrypt(self, value: str) -> str:
        if self.fernet:
            return self.fernet.encrypt(value.encode("utf-8")).decode("utf-8")
        return base64.b64encode(value.encode("utf-8")).decode("utf-8")

    def _decrypt(self, value: str) -> str:
        if not value:
            return ""
        if self.fernet:
            try:
                return self.fernet.decrypt(value.encode("utf-8")).decode("utf-8")
            except InvalidToken:
                # Fall through to base64/plain for dev/test migrations.
                pass
        try:
            return base64.b64decode(value.encode("utf-8")).decode("utf-8")
        except Exception:
            return value

    @staticmethod
    def _truncate_diagnostic_output(value: str, limit: int = _REMOTE_OUTPUT_LIMIT) -> str:
        text = (value or "").strip()
        if len(text) <= limit:
            return text
        return text[:limit].rstrip() + "...[truncated]"

    @staticmethod
    def _filter_known_host_warnings(value: str) -> str:
        kept: list[str] = []
        for line in (value or "").splitlines():
            stripped = line.strip()
            if stripped.startswith("Warning: Permanently added ") and "to the list of known hosts." in stripped:
                continue
            if stripped.startswith("Permanently added '") and "to the list of known hosts." in stripped:
                continue
            kept.append(line)
        return "\n".join(kept).strip()

    @staticmethod
    def _redact_command_summary(command: str) -> str:
        redacted = re.sub(
            r"(--provisioning-token\s+)(?:'[^']*'|\"[^\"]*\"|\S+)",
            r"\1<redacted>",
            command,
        )
        redacted = re.sub(
            r"(--password-b64\s+)(?:'[^']*'|\"[^\"]*\"|\S+)",
            r"\1<redacted>",
            redacted,
        )
        return redacted

    @staticmethod
    def _wrap_remote_command(command: str) -> str:
        script = (
            f"{command}\n"
            "sw_exit_code=$?\n"
            f"printf '\\n{_REMOTE_EXIT_MARKER}%s\\n' \"$sw_exit_code\"\n"
            "exit 0\n"
        )
        return "sh -lc " + shlex.quote(script)

    @staticmethod
    def _extract_remote_exit_code(stdout: str) -> tuple[str, Optional[int]]:
        exit_code: Optional[int] = None
        kept: list[str] = []
        for line in (stdout or "").splitlines():
            if line.startswith(_REMOTE_EXIT_MARKER):
                raw = line[len(_REMOTE_EXIT_MARKER):].strip()
                if raw.isdigit():
                    exit_code = int(raw)
                    continue
            kept.append(line)
        return "\n".join(kept).strip(), exit_code

    @staticmethod
    def _generate_username() -> str:
        # Keep to safe characters for shell scripts and legacy auth backends.
        return f"sw_{secrets.token_hex(10)}"

    @staticmethod
    def _generate_password() -> str:
        # URL-safe base64; avoids quotes/whitespace for scripting and config formats.
        return secrets.token_urlsafe(24)

    @staticmethod
    def _local_host_aliases() -> set[str]:
        aliases = {"127.0.0.1", "localhost", os.uname().nodename.strip().lower()}

        for cmd in (["hostname", "-f"], ["hostname"], ["hostname", "-I"]):
            try:
                raw = subprocess.check_output(cmd, text=True, timeout=2)
            except Exception:
                continue
            for token in raw.split():
                text = token.strip().lower()
                if text:
                    aliases.add(text)

        try:
            raw = subprocess.check_output(["ip", "-4", "route", "get", "1.1.1.1"], text=True, timeout=2)
        except Exception:
            raw = ""
        parts = raw.split()
        for index, part in enumerate(parts):
            if part == "src" and index + 1 < len(parts):
                aliases.add(parts[index + 1].strip().lower())

        return aliases

    @classmethod
    def _should_run_local(cls, server: Any) -> bool:
        server_host = str(getattr(server, "public_ip", None) or "").strip().lower()
        if not server_host:
            return False
        return server_host in cls._local_host_aliases()

    @staticmethod
    def _parse_bool_env(name: str, default: bool) -> bool:
        raw = os.getenv(name)
        if raw is None:
            return default
        return raw.strip().lower() in {"1", "true", "yes", "on"}

    @staticmethod
    def _parse_valid_days(name: str, default: int, *, minimum: int = 1, maximum: int = 825) -> int:
        raw = os.getenv(name, str(default)).strip()
        try:
            value = int(raw)
        except ValueError:
            return default
        return max(minimum, min(maximum, value))

    @staticmethod
    def _utc_now() -> datetime:
        return datetime.now(timezone.utc)

    @staticmethod
    def _to_naive_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value
        return value.astimezone(timezone.utc).replace(tzinfo=None)

    @staticmethod
    def _parse_iso8601(value: Optional[str]) -> Optional[datetime]:
        if not value:
            return None
        text = value.strip()
        if not text:
            return None
        text = text.replace("Z", "+00:00")
        dt = datetime.fromisoformat(text)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)

    @staticmethod
    def _b64url_encode(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")

    @staticmethod
    def _b64url_decode(data: str) -> bytes:
        padding = "=" * (-len(data) % 4)
        return base64.urlsafe_b64decode((data + padding).encode("ascii"))

    def _provisioning_secret(self) -> str:
        secret = os.getenv("SECUREWAVE_PROVISIONING_TOKEN_SECRET", "").strip()
        if not secret:
            if is_production() and not self.testing:
                raise RuntimeError("SECUREWAVE_PROVISIONING_TOKEN_SECRET is required for certificate provisioning")
            # Dev/test fallback derived from local process/runtime state.
            seed = (
                os.getenv("WG_ENCRYPTION_KEY", "").strip()
                or os.getenv("AUTH_ENCRYPTION_KEY", "").strip()
                or f"{os.uname().nodename}:{os.getpid()}:{int(datetime.now().timestamp())}"
            )
            secret = hashlib.sha256(seed.encode("utf-8")).hexdigest()
        return secret

    def _mint_provisioning_token(
        self,
        *,
        subject: str,
        protocol: str,
        ttl_seconds: int,
        secret: Optional[str] = None,
    ) -> tuple[str, str, datetime]:
        now = self._utc_now()
        expires = now + timedelta(seconds=max(30, ttl_seconds))
        payload = {
            "sub": subject,
            "proto": protocol,
            "iat": int(now.timestamp()),
            "exp": int(expires.timestamp()),
            "nonce": secrets.token_urlsafe(12),
        }
        payload_bytes = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        body = self._b64url_encode(payload_bytes)
        signing_secret = secret or self._provisioning_secret()
        signature = hmac.new(
            signing_secret.encode("utf-8"),
            body.encode("ascii"),
            digestmod=hashlib.sha256,
        ).digest()
        token = f"{body}.{self._b64url_encode(signature)}"
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        return token, token_hash, expires

    @staticmethod
    def _parse_json_from_stdout(stdout: str) -> dict[str, Any]:
        text = (stdout or "").strip()
        if not text:
            raise ValueError("Empty provisioning response")

        # Prefer explicit JSON line when scripts emit progress logs.
        for line in reversed(text.splitlines()):
            candidate = line.strip()
            if candidate.startswith("{") and candidate.endswith("}"):
                try:
                    parsed = json.loads(candidate)
                    if isinstance(parsed, dict):
                        return parsed
                except json.JSONDecodeError:
                    continue

        parsed = json.loads(text)
        if not isinstance(parsed, dict):
            raise ValueError("Provisioning response must be a JSON object")
        return parsed

    @staticmethod
    def _payload_failure_message(payload: dict[str, Any], fallback: str) -> str:
        return (
            str(payload.get("code") or "").strip()
            or str(payload.get("message") or "").strip()
            or fallback
        )

    async def _resolve_script_payload(
        self,
        *,
        server: Any,
        payload: dict[str, Any],
        required_keys: list[str],
    ) -> dict[str, Any]:
        if payload.get("ok") is False:
            raise RuntimeError(self._payload_failure_message(payload, "provisioning failed"))

        if all(str(payload.get(key) or "").strip() for key in required_keys):
            return payload

        artifact_path = str(payload.get("artifact_path") or "").strip()
        if not artifact_path:
            return payload
        if not artifact_path.startswith("/var/lib/securewave/pki/"):
            raise RuntimeError("Unsafe provisioning artifact path")

        cmd = " ".join(
            [
                "sudo",
                "cat",
                shlex.quote(artifact_path),
            ]
        )
        ok, stdout, stderr = await self._run_remote_script(server=server, command=cmd)
        if not ok:
            raise RuntimeError((stderr or stdout or "provisioning artifact retrieval failed").strip())
        artifact_payload = self._parse_json_from_stdout(stdout)
        if artifact_payload.get("ok") is False:
            raise RuntimeError(self._payload_failure_message(artifact_payload, "provisioning failed"))

        merged = dict(payload)
        merged.update(artifact_payload)
        return merged

    def _common_name(self, *, protocol: str, user_id: int, device_id: int, revision: int) -> str:
        return f"sw-{protocol}-u{user_id}-d{device_id}-r{revision}"

    def _upsert_certificate_record(
        self,
        *,
        protocol: str,
        user_id: int,
        device_id: int,
        server_id: int,
        common_name: str,
        cert_serial: Optional[str],
        cert_fingerprint_sha256: Optional[str],
        profile_expires_at: Optional[datetime],
        provisioning_token_hash: str,
        metadata: Optional[dict[str, Any]] = None,
    ) -> VPNCredential:
        record = (
            self.db.query(VPNCredential)
            .filter(
                VPNCredential.user_id == user_id,
                VPNCredential.device_id == device_id,
                VPNCredential.server_id == server_id,
                VPNCredential.protocol == protocol,
            )
            .first()
        )
        now = self._utc_now()
        if record is None:
            record = VPNCredential(
                user_id=user_id,
                device_id=device_id,
                server_id=server_id,
                protocol=protocol,
                credential_type="client_certificate",
                username=common_name,
                password_encrypted=self._encrypt(secrets.token_urlsafe(24)),
                revision=1,
            )
            self.db.add(record)
            self.db.flush()
        else:
            current_revision = int(record.revision or 1)
            record.revision = current_revision + 1 if record.username != common_name else current_revision

        record.credential_type = "client_certificate"
        record.username = common_name
        record.cert_serial = cert_serial
        record.cert_fingerprint_sha256 = cert_fingerprint_sha256
        record.profile_expires_at = self._to_naive_utc(profile_expires_at) if profile_expires_at else None
        record.last_provisioned_at = self._to_naive_utc(now)
        record.last_rotated_at = self._to_naive_utc(now)
        record.provisioning_token_hash = provisioning_token_hash
        record.revoked_at = None
        record.revoke_reason = None
        record.metadata_json = metadata or {}

        self.db.add(record)
        self.db.commit()
        self.db.refresh(record)
        return record

    def _upsert_userpass_record(
        self,
        *,
        protocol: str,
        user_id: int,
        device_id: int,
        server_id: int,
        username: str,
        password: str,
    ) -> VPNCredential:
        record = (
            self.db.query(VPNCredential)
            .filter(
                VPNCredential.user_id == user_id,
                VPNCredential.device_id == device_id,
                VPNCredential.server_id == server_id,
                VPNCredential.protocol == protocol,
            )
            .first()
        )
        now = self._utc_now()
        if record is None:
            record = VPNCredential(
                user_id=user_id,
                device_id=device_id,
                server_id=server_id,
                protocol=protocol,
                username=username,
                password_encrypted=self._encrypt(password),
                credential_type="username_password",
                revision=1,
            )
            self.db.add(record)
            self.db.commit()
            self.db.refresh(record)
            return record

        record.username = username
        record.password_encrypted = self._encrypt(password)
        record.credential_type = "username_password"
        record.last_provisioned_at = self._to_naive_utc(now)
        record.profile_expires_at = None
        record.cert_serial = None
        record.cert_fingerprint_sha256 = None
        record.provisioning_token_hash = None
        record.metadata_json = {"auth_mode": "username_password"}
        self.db.add(record)
        self.db.commit()
        self.db.refresh(record)
        return record

    async def _run_remote_script(
        self,
        *,
        server: Any,
        command: str,
    ) -> tuple[bool, str, str]:
        result = await self._run_remote_script_detailed(server=server, command=command)
        return result.ok, result.stdout, result.stderr

    async def _run_remote_script_detailed(
        self,
        *,
        server: Any,
        command: str,
    ) -> RemoteScriptExecution:
        if self._should_run_local(server):
            started = time.monotonic()
            wrapped_command = self._wrap_remote_command(command)
            proc = subprocess.run(
                wrapped_command,
                shell=True,
                text=True,
                capture_output=True,
                executable="/bin/bash",
            )
            duration_ms = int((time.monotonic() - started) * 1000)
            clean_stdout, exit_code = self._extract_remote_exit_code(proc.stdout)
            if exit_code is None:
                exit_code = proc.returncode
            return RemoteScriptExecution(
                ok=exit_code == 0,
                stdout=clean_stdout,
                stderr=proc.stderr.strip(),
                exit_code=exit_code,
                duration_ms=duration_ms,
                command_summary=self._redact_command_summary(command),
            )

        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        started = time.monotonic()
        transport_ok, stdout, stderr = await manager.run_ssh_command(
            conn,
            self._wrap_remote_command(command),
        )
        duration_ms = int((time.monotonic() - started) * 1000)
        clean_stdout, exit_code = self._extract_remote_exit_code(stdout)
        filtered_stderr = self._filter_known_host_warnings(stderr)
        if exit_code is None:
            exit_code = 0 if transport_ok else None
        return RemoteScriptExecution(
            ok=transport_ok and exit_code == 0,
            stdout=clean_stdout,
            stderr=filtered_stderr,
            exit_code=exit_code,
            duration_ms=duration_ms,
            command_summary=self._redact_command_summary(command),
        )

    def _openvpn_testing_payload(self, *, server: Any, common_name: str, valid_days: int) -> dict[str, Any]:
        expires = self._utc_now() + timedelta(days=max(1, valid_days))
        server_host = (
            (getattr(server, "openvpn_endpoint", None) or "").strip()
            or (getattr(server, "public_ip", None) or "").strip()
            or "198.51.100.10"
        )
        openvpn_port = getattr(server, "openvpn_port", None) or 1194
        try:
            port = int(openvpn_port)
        except (TypeError, ValueError):
            port = 1194
        transport = (getattr(server, "openvpn_transport", None) or "udp").strip().lower()
        if transport not in {"udp", "tcp"}:
            transport = "udp"
        ovpn = "\n".join(
            [
                "client",
                "dev tun",
                f"proto {transport}",
                f"remote {server_host} {port}",
                "nobind",
                "persist-key",
                "persist-tun",
                "remote-cert-tls server",
                "verb 3",
                "<ca>",
                "-----BEGIN CERTIFICATE-----",
                "REDACTED-CA",
                "-----END CERTIFICATE-----",
                "</ca>",
                "<cert>",
                "-----BEGIN CERTIFICATE-----",
                f"REDACTED-CLIENT-{common_name}",
                "-----END CERTIFICATE-----",
                "</cert>",
                "<key>",
                "REDACTED-PRIVATE-KEY",
                "</key>",
                "",
            ]
        )
        return {
            "ovpn_config_b64": base64.b64encode(ovpn.encode("utf-8")).decode("ascii"),
            "cert_serial": f"test-{common_name}",
            "fingerprint_sha256": hashlib.sha256(common_name.encode("utf-8")).hexdigest(),
            "expires_at": expires.isoformat().replace("+00:00", "Z"),
        }

    def _ikev2_testing_payload(self, *, common_name: str, server_host: str, remote_id: Optional[str], valid_days: int) -> dict[str, Any]:
        expires = self._utc_now() + timedelta(days=max(1, valid_days))
        ca_pem = "\n".join(
            [
                "-----BEGIN CERTIFICATE-----",
                "REDACTED-IKEV2-CA",
                "-----END CERTIFICATE-----",
            ]
        )
        return {
            "server": server_host,
            "remote_id": remote_id,
            "client_pkcs12_b64": base64.b64encode(f"PKCS12-REDACTED-{common_name}".encode("utf-8")).decode("ascii"),
            "client_pkcs12_password": "REDACTED-PASSWORD",
            "ca_cert_pem_b64": base64.b64encode(ca_pem.encode("utf-8")).decode("ascii"),
            "cert_serial": f"test-{common_name}",
            "fingerprint_sha256": hashlib.sha256(common_name.encode("utf-8")).hexdigest(),
            "expires_at": expires.isoformat().replace("+00:00", "Z"),
        }

    def list_user_credentials(
        self,
        *,
        user_id: int,
        device_id: Optional[int] = None,
        protocol: Optional[str] = None,
    ) -> list[VPNCredential]:
        query = self.db.query(VPNCredential).filter(VPNCredential.user_id == user_id)
        if device_id is not None:
            query = query.filter(VPNCredential.device_id == device_id)
        if protocol:
            query = query.filter(VPNCredential.protocol == protocol.strip().lower())
        return query.order_by(VPNCredential.updated_at.desc(), VPNCredential.id.desc()).all()

    def get_user_credential(self, *, user_id: int, credential_id: int) -> Optional[VPNCredential]:
        return (
            self.db.query(VPNCredential)
            .filter(VPNCredential.user_id == user_id, VPNCredential.id == credential_id)
            .first()
        )

    async def issue_openvpn_certificate_profile(
        self,
        *,
        user_id: int,
        device_id: int,
        server: Any,
    ) -> ProvisionedOpenVpnProfile:
        valid_days = self._parse_valid_days("SECUREWAVE_OPENVPN_CERT_VALID_DAYS", 30, minimum=1, maximum=365)
        revision_seed = 1
        existing = (
            self.db.query(VPNCredential)
            .filter(
                VPNCredential.user_id == user_id,
                VPNCredential.device_id == device_id,
                VPNCredential.server_id == server.id,
                VPNCredential.protocol == "openvpn",
            )
            .first()
        )
        if existing is not None and existing.revoked_at is None:
            revision_seed = int(existing.revision or 1)
            if (existing.credential_type or "").strip() != "client_certificate":
                revision_seed += 1

        common_name = self._common_name(protocol="ovpn", user_id=user_id, device_id=device_id, revision=revision_seed)
        provisioning_secret = self._provisioning_secret()
        token, token_hash, token_expires = self._mint_provisioning_token(
            subject=common_name,
            protocol="openvpn",
            ttl_seconds=self._parse_valid_days("SECUREWAVE_PROVISIONING_TOKEN_TTL_SECONDS", 300, minimum=30, maximum=3600),
            secret=provisioning_secret,
        )

        if self.testing:
            data = self._openvpn_testing_payload(server=server, common_name=common_name, valid_days=valid_days)
            provisioned = True
            status_message = "issued_via_testing_payload"
        else:
            issue_cmd = " ".join(
                [
                    "sudo",
                    "env",
                    f"SECUREWAVE_PROVISIONING_TOKEN_SECRET={shlex.quote(provisioning_secret)}",
                    "/usr/local/bin/securewave-openvpn-issue-client",
                    "--common-name",
                    shlex.quote(common_name),
                    "--valid-days",
                    shlex.quote(str(valid_days)),
                    "--provisioning-token",
                    shlex.quote(token),
                    "--output",
                    "json",
                ]
            )
            ok, stdout, stderr = await self._run_remote_script(server=server, command=issue_cmd)
            if not ok:
                raise RuntimeError((stderr or stdout or "openvpn provisioning failed").strip())
            data = await self._resolve_script_payload(
                server=server,
                payload=self._parse_json_from_stdout(stdout),
                required_keys=["ovpn_config_b64"],
            )
            provisioned = True
            status_message = self._payload_failure_message(data, "credential_provisioned")

        ovpn_b64 = (data.get("ovpn_config_b64") or "").strip()
        if not ovpn_b64:
            raise RuntimeError("OpenVPN provisioning response missing ovpn_config_b64")
        ovpn_config = base64.b64decode(ovpn_b64.encode("ascii")).decode("utf-8")

        cert_serial = (data.get("cert_serial") or "").strip() or None
        fingerprint = (data.get("fingerprint_sha256") or "").strip() or None
        expires_at = self._parse_iso8601(data.get("expires_at"))

        record = self._upsert_certificate_record(
            protocol="openvpn",
            user_id=user_id,
            device_id=device_id,
            server_id=server.id,
            common_name=common_name,
            cert_serial=cert_serial,
            cert_fingerprint_sha256=fingerprint,
            profile_expires_at=expires_at,
            provisioning_token_hash=token_hash,
            metadata={
                "auth_mode": "mtls",
                "token_expires_at": token_expires.isoformat(),
            },
        )

        return ProvisionedOpenVpnProfile(
            credential_id=record.id,
            revision=int(record.revision or 1),
            common_name=common_name,
            ovpn_config=ovpn_config,
            cert_serial=cert_serial,
            cert_fingerprint_sha256=fingerprint,
            expires_at=expires_at,
            provisioned_on_server=provisioned,
            status_message=status_message,
        )

    async def issue_ikev2_certificate_profile(
        self,
        *,
        user_id: int,
        device_id: int,
        server: Any,
    ) -> ProvisionedIkev2Profile:
        valid_days = self._parse_valid_days("SECUREWAVE_IKEV2_CERT_VALID_DAYS", 30, minimum=1, maximum=365)
        revision_seed = 1
        existing = (
            self.db.query(VPNCredential)
            .filter(
                VPNCredential.user_id == user_id,
                VPNCredential.device_id == device_id,
                VPNCredential.server_id == server.id,
                VPNCredential.protocol == "ikev2",
            )
            .first()
        )
        if existing is not None and existing.revoked_at is None:
            revision_seed = int(existing.revision or 1)
            if (existing.credential_type or "").strip() != "client_certificate":
                revision_seed += 1

        common_name = self._common_name(protocol="ikev2", user_id=user_id, device_id=device_id, revision=revision_seed)
        provisioning_secret = self._provisioning_secret()
        token, token_hash, token_expires = self._mint_provisioning_token(
            subject=common_name,
            protocol="ikev2",
            ttl_seconds=self._parse_valid_days("SECUREWAVE_PROVISIONING_TOKEN_TTL_SECONDS", 300, minimum=30, maximum=3600),
            secret=provisioning_secret,
        )

        remote_id = (getattr(server, "ikev2_remote_id", None) or "").strip() or None
        server_host = remote_id or (getattr(server, "public_ip", None) or "").strip()
        if not server_host:
            raise RuntimeError("IKEv2 server endpoint is not configured")

        if self.testing:
            data = self._ikev2_testing_payload(
                common_name=common_name,
                server_host=server_host,
                remote_id=remote_id,
                valid_days=valid_days,
            )
            provisioned = True
            status_message = "issued_via_testing_payload"
        else:
            issue_cmd = " ".join(
                [
                    "sudo",
                    "env",
                    f"SECUREWAVE_PROVISIONING_TOKEN_SECRET={shlex.quote(provisioning_secret)}",
                    "/usr/local/bin/securewave-ikev2-issue-client",
                    "--common-name",
                    shlex.quote(common_name),
                    "--valid-days",
                    shlex.quote(str(valid_days)),
                    "--provisioning-token",
                    shlex.quote(token),
                    "--server",
                    shlex.quote(server_host),
                    "--remote-id",
                    shlex.quote(remote_id or ""),
                    "--output",
                    "json",
                ]
            )
            result = await self._run_remote_script_detailed(server=server, command=issue_cmd)
            stdout = result.stdout
            if not result.ok:
                raise RemoteScriptError(
                    "ikev2 provisioning failed",
                    exit_code=result.exit_code,
                    duration_ms=result.duration_ms,
                    command_summary=result.command_summary,
                    filtered_stderr=result.stderr,
                    stdout=stdout,
                )
            data = await self._resolve_script_payload(
                server=server,
                payload=self._parse_json_from_stdout(stdout),
                required_keys=["client_pkcs12_b64", "client_pkcs12_password"],
            )
            provisioned = True
            status_message = self._payload_failure_message(data, "credential_provisioned")

        pkcs12_b64 = (data.get("client_pkcs12_b64") or "").strip()
        if not pkcs12_b64:
            raise RuntimeError("IKEv2 provisioning response missing client_pkcs12_b64")

        pkcs12_password = (data.get("client_pkcs12_password") or "").strip()
        if not pkcs12_password:
            raise RuntimeError("IKEv2 provisioning response missing client_pkcs12_password")

        ca_b64 = (data.get("ca_cert_pem_b64") or "").strip()
        ca_cert_pem = base64.b64decode(ca_b64.encode("ascii")).decode("utf-8") if ca_b64 else None

        cert_serial = (data.get("cert_serial") or "").strip() or None
        fingerprint = (data.get("fingerprint_sha256") or "").strip() or None
        expires_at = self._parse_iso8601(data.get("expires_at"))

        record = self._upsert_certificate_record(
            protocol="ikev2",
            user_id=user_id,
            device_id=device_id,
            server_id=server.id,
            common_name=common_name,
            cert_serial=cert_serial,
            cert_fingerprint_sha256=fingerprint,
            profile_expires_at=expires_at,
            provisioning_token_hash=token_hash,
            metadata={
                "auth_mode": "eap-tls",
                "token_expires_at": token_expires.isoformat(),
            },
        )

        return ProvisionedIkev2Profile(
            credential_id=record.id,
            revision=int(record.revision or 1),
            common_name=common_name,
            server=server_host,
            remote_id=remote_id,
            ca_cert_pem=ca_cert_pem,
            client_pkcs12_base64=pkcs12_b64,
            client_pkcs12_password=pkcs12_password,
            cert_serial=cert_serial,
            cert_fingerprint_sha256=fingerprint,
            expires_at=expires_at,
            provisioned_on_server=provisioned,
            status_message=status_message,
        )

    async def revoke_certificate(
        self,
        *,
        credential: VPNCredential,
        server: Any,
        reason: str,
    ) -> tuple[bool, str]:
        if credential.protocol not in {"openvpn", "ikev2"}:
            return False, "unsupported_protocol"

        if credential.revoked_at is not None:
            return True, "already_revoked"

        if credential.credential_type != "client_certificate":
            credential.revoked_at = self._to_naive_utc(self._utc_now())
            credential.revoke_reason = reason[:128]
            self.db.add(credential)
            self.db.commit()
            return True, "revoked_metadata_only"

        if not self.testing:
            script = (
                "/usr/local/bin/securewave-openvpn-revoke-client"
                if credential.protocol == "openvpn"
                else "/usr/local/bin/securewave-ikev2-revoke-client"
            )
            cmd = " ".join(
                [
                    "sudo",
                    script,
                    "--common-name",
                    shlex.quote(credential.username),
                ]
            )
            ok, stdout, stderr = await self._run_remote_script(server=server, command=cmd)
            if not ok:
                return False, (stderr or stdout or "credential revoke failed").strip()

        credential.revoked_at = self._to_naive_utc(self._utc_now())
        credential.revoke_reason = (reason or "manual_revoke")[:128]
        self.db.add(credential)
        self.db.commit()
        self.db.refresh(credential)
        return True, "revoked"

    async def rotate_certificate(
        self,
        *,
        credential: VPNCredential,
        server: Any,
    ) -> tuple[bool, str]:
        ok, message = await self.revoke_certificate(
            credential=credential,
            server=server,
            reason="rotated",
        )
        if not ok and message != "already_revoked":
            return False, message
        return True, "rotated"

    def get_or_create(
        self,
        *,
        user_id: int,
        device_id: int,
        server_id: int,
        protocol: str,
    ) -> VpnProtocolCredentials:
        normalized = (protocol or "").strip().lower()
        if normalized not in {"openvpn", "ikev2"}:
            raise ValueError("Unsupported credential protocol")

        existing = (
            self.db.query(VPNCredential)
            .filter(
                VPNCredential.user_id == user_id,
                VPNCredential.device_id == device_id,
                VPNCredential.server_id == server_id,
                VPNCredential.protocol == normalized,
                VPNCredential.revoked_at.is_(None),
            )
            .first()
        )
        if existing:
            return VpnProtocolCredentials(
                username=existing.username,
                password=self._decrypt(existing.password_encrypted),
                created=False,
            )

        username = self._generate_username()
        password = self._generate_password()
        self._upsert_userpass_record(
            protocol=normalized,
            user_id=user_id,
            device_id=device_id,
            server_id=server_id,
            username=username,
            password=password,
        )

        return VpnProtocolCredentials(username=username, password=password, created=True)
