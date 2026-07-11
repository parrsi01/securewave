"""Transactional VPN usage session and counter handling.

The API records control-plane metering state only.  It never represents a
client-side tunnel as proven, and it deliberately stores counters rather than
traffic destinations.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models.vpn_connection import VPNConnection
from models.vpn_usage_event import VPNUsageEvent
from models.wireguard_peer import WireGuardPeer


class UsageMeteringError(Exception):
    """Base error for a safe client-facing metering failure."""

    status_code = 409
    detail = "Usage session update could not be applied."


class UsageSessionNotFound(UsageMeteringError):
    status_code = 404
    detail = "Usage session not found."


class UsageSessionFinalized(UsageMeteringError):
    detail = "Usage session is already finalized."


class UsageSequenceConflict(UsageMeteringError):
    detail = "Usage sequence must advance monotonically."


class UsageIdempotencyConflict(UsageMeteringError):
    detail = "Idempotency key was already used for a different usage event."


class UsageActiveSessionConflict(UsageMeteringError):
    detail = "Device already has an active usage session."


class UsageDeviceServerMismatch(UsageMeteringError):
    detail = "Usage device is not assigned to the requested server."


@dataclass(frozen=True)
class MeteringResult:
    connection: VPNConnection
    idempotent: bool


class UsageMeteringService:
    """Small owner-scoped persistence boundary for metering state."""

    def __init__(self, db: Session):
        self.db = db

    def _owned_connection(self, user_id: int, connection_id: int) -> VPNConnection:
        connection = self.db.query(VPNConnection).filter(
            VPNConnection.id == connection_id,
            VPNConnection.user_id == user_id,
        ).first()
        if connection is None:
            raise UsageSessionNotFound()
        return connection

    def start_session(
        self,
        *,
        user_id: int,
        device_id: int,
        server_id: int,
        protocol: str,
        idempotency_key: str,
    ) -> MeteringResult:
        existing = self.db.query(VPNConnection).filter(
            VPNConnection.user_id == user_id,
            VPNConnection.start_idempotency_key == idempotency_key,
        ).first()
        if existing is not None:
            if not self._start_matches(
                existing,
                device_id=device_id,
                server_id=server_id,
                protocol=protocol,
            ):
                raise UsageIdempotencyConflict()
            return MeteringResult(existing, idempotent=True)

        peer = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.id == device_id,
            WireGuardPeer.user_id == user_id,
            WireGuardPeer.is_active.is_(True),
            WireGuardPeer.is_revoked.is_(False),
        ).first()
        if peer is None:
            raise UsageSessionNotFound()
        if peer.server_id != server_id:
            raise UsageDeviceServerMismatch()

        now = datetime.utcnow()
        # A reconnect finalizes any prior control-plane record for this device.
        self.db.execute(
            update(VPNConnection)
            .where(
                VPNConnection.user_id == user_id,
                VPNConnection.device_id == device_id,
                VPNConnection.disconnected_at.is_(None),
            )
            .values(disconnected_at=now, finalization_reason="reconnect")
        )
        connection = VPNConnection(
            user_id=user_id,
            server_id=server_id,
            device_id=device_id,
            protocol=protocol,
            start_idempotency_key=idempotency_key,
            connected_at=now,
        )
        self.db.add(connection)
        self.db.execute(
            update(WireGuardPeer)
            .where(WireGuardPeer.id == device_id, WireGuardPeer.user_id == user_id)
            .values(connection_count=WireGuardPeer.connection_count + 1)
        )
        try:
            self.db.commit()
        except IntegrityError:
            self.db.rollback()
            existing = self.db.query(VPNConnection).filter(
                VPNConnection.user_id == user_id,
                VPNConnection.start_idempotency_key == idempotency_key,
            ).first()
            if existing is not None:
                if not self._start_matches(
                    existing,
                    device_id=device_id,
                    server_id=server_id,
                    protocol=protocol,
                ):
                    raise UsageIdempotencyConflict()
                return MeteringResult(existing, idempotent=True)
            # A different concurrent start key may lose the active-device
            # uniqueness race.  It is not an idempotent retry: returning the
            # winner's session would falsely acknowledge an unrecorded key.
            raise UsageActiveSessionConflict()
        self.db.refresh(connection)
        return MeteringResult(connection, idempotent=False)

    @staticmethod
    def _start_matches(
        connection: VPNConnection,
        *,
        device_id: int,
        server_id: int,
        protocol: str,
    ) -> bool:
        return (
            connection.device_id == device_id
            and connection.server_id == server_id
            and connection.protocol == protocol
        )

    def increment(
        self,
        *,
        user_id: int,
        connection_id: int,
        sequence: int,
        bytes_sent: int,
        bytes_received: int,
        idempotency_key: str,
    ) -> MeteringResult:
        existing_event = self.db.query(VPNUsageEvent).filter(
            VPNUsageEvent.user_id == user_id,
            VPNUsageEvent.idempotency_key == idempotency_key,
        ).first()
        if existing_event is not None:
            if (
                existing_event.connection_id != connection_id
                or existing_event.sequence != sequence
                or existing_event.bytes_sent != bytes_sent
                or existing_event.bytes_received != bytes_received
            ):
                raise UsageIdempotencyConflict()
            return MeteringResult(
                self._owned_connection(user_id, connection_id), idempotent=True
            )

        connection = self._owned_connection(user_id, connection_id)
        if connection.disconnected_at is not None:
            raise UsageSessionFinalized()

        now = datetime.utcnow()
        event = VPNUsageEvent(
            connection_id=connection_id,
            user_id=user_id,
            idempotency_key=idempotency_key,
            sequence=sequence,
            bytes_sent=bytes_sent,
            bytes_received=bytes_received,
        )
        try:
            # Reserve the idempotency key first.  A concurrent duplicate
            # therefore rolls back without double-counting the connection.
            self.db.add(event)
            self.db.flush()
            updated = self.db.execute(
                update(VPNConnection)
                .where(
                    VPNConnection.id == connection_id,
                    VPNConnection.user_id == user_id,
                    VPNConnection.disconnected_at.is_(None),
                    VPNConnection.last_meter_sequence < sequence,
                )
                .values(
                    total_bytes_sent=VPNConnection.total_bytes_sent + bytes_sent,
                    total_bytes_received=VPNConnection.total_bytes_received + bytes_received,
                    last_meter_sequence=sequence,
                    last_metered_at=now,
                )
            )
            if updated.rowcount != 1:
                self.db.rollback()
                current = self._owned_connection(user_id, connection_id)
                if current.disconnected_at is not None:
                    raise UsageSessionFinalized()
                raise UsageSequenceConflict()

            if connection.device_id is not None:
                self.db.execute(
                    update(WireGuardPeer)
                    .where(
                        WireGuardPeer.id == connection.device_id,
                        WireGuardPeer.user_id == user_id,
                        WireGuardPeer.is_revoked.is_(False),
                    )
                    .values(
                        total_data_sent=WireGuardPeer.total_data_sent + bytes_sent,
                        total_data_received=WireGuardPeer.total_data_received + bytes_received,
                        last_handshake_at=now,
                    )
                )
            self.db.commit()
        except IntegrityError:
            self.db.rollback()
            existing_event = self.db.query(VPNUsageEvent).filter(
                VPNUsageEvent.user_id == user_id,
                VPNUsageEvent.idempotency_key == idempotency_key,
            ).first()
            if existing_event is not None:
                if (
                    existing_event.connection_id == connection_id
                    and existing_event.sequence == sequence
                    and existing_event.bytes_sent == bytes_sent
                    and existing_event.bytes_received == bytes_received
                ):
                    return MeteringResult(
                        self._owned_connection(user_id, connection_id), idempotent=True
                    )
                raise UsageIdempotencyConflict()
            raise

        return MeteringResult(self._owned_connection(user_id, connection_id), idempotent=False)

    def finalize(
        self,
        *,
        user_id: int,
        connection_id: int,
        idempotency_key: Optional[str],
        reason: str,
    ) -> MeteringResult:
        connection = self._owned_connection(user_id, connection_id)
        if connection.disconnected_at is not None:
            if idempotency_key and connection.finalization_idempotency_key not in {None, idempotency_key}:
                raise UsageIdempotencyConflict()
            return MeteringResult(connection, idempotent=True)

        now = datetime.utcnow()
        updated = self.db.execute(
            update(VPNConnection)
            .where(
                VPNConnection.id == connection_id,
                VPNConnection.user_id == user_id,
                VPNConnection.disconnected_at.is_(None),
            )
            .values(
                disconnected_at=now,
                finalization_idempotency_key=idempotency_key,
                finalization_reason=reason,
            )
        )
        if updated.rowcount != 1:
            self.db.rollback()
            return MeteringResult(self._owned_connection(user_id, connection_id), idempotent=True)
        self.db.commit()
        return MeteringResult(self._owned_connection(user_id, connection_id), idempotent=False)
