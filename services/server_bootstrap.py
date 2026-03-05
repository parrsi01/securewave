from __future__ import annotations

import logging

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models.vpn_server import VPNServer

logger = logging.getLogger(__name__)

_PLACEHOLDER_PUBLIC_IP = "138.199.204.139"
_PLACEHOLDER_WG_PORT = 51820

_DEFAULT_SERVERS = (
    {
        "server_id": "de-nue-1",
        "location": "Nuremberg",
        "country": "Germany",
        "country_code": "DE",
        "city": "Nuremberg",
        "region": "Europe",
        "hcloud_location": "nbg1",
        "wg_public_key": "BOOTSTRAP_WG_PUBKEY_DE_NUE_1",
        "tier_restriction": None,
    },
    {
        "server_id": "de-fra-1",
        "location": "Frankfurt",
        "country": "Germany",
        "country_code": "DE",
        "city": "Frankfurt",
        "region": "Europe",
        "hcloud_location": "fsn1",
        "wg_public_key": "BOOTSTRAP_WG_PUBKEY_DE_FRA_1",
        "tier_restriction": None,
    },
    {
        "server_id": "ch-zrh-1",
        "location": "Zurich",
        "country": "Switzerland",
        "country_code": "CH",
        "city": "Zurich",
        "region": "Europe",
        "hcloud_location": "fsn1",
        "wg_public_key": "BOOTSTRAP_WG_PUBKEY_CH_ZRH_1",
        "tier_restriction": "premium",
    },
    {
        "server_id": "nl-ams-1",
        "location": "Amsterdam",
        "country": "Netherlands",
        "country_code": "NL",
        "city": "Amsterdam",
        "region": "Europe",
        "hcloud_location": "fsn1",
        "wg_public_key": "BOOTSTRAP_WG_PUBKEY_NL_AMS_1",
        "tier_restriction": "premium",
    },
    {
        "server_id": "fr-par-1",
        "location": "Paris",
        "country": "France",
        "country_code": "FR",
        "city": "Paris",
        "region": "Europe",
        "hcloud_location": "fsn1",
        "wg_public_key": "BOOTSTRAP_WG_PUBKEY_FR_PAR_1",
        "tier_restriction": "premium",
    },
)


def ensure_default_servers(session: Session) -> None:
    """
    Ensure the default server inventory exists.

    The existing schema has no `region_code` field, so the requested region
    codes are persisted in `VPNServer.server_id`.
    """
    default_ids = [str(item["server_id"]) for item in _DEFAULT_SERVERS]
    existing_ids = {
        row[0]
        for row in session.query(VPNServer.server_id)
        .filter(VPNServer.server_id.in_(default_ids))
        .all()
    }

    inserted = 0
    for item in _DEFAULT_SERVERS:
        server_id = str(item["server_id"])
        if server_id in existing_ids:
            continue
        session.add(
            VPNServer(
                server_id=server_id,
                location=str(item["location"]),
                country=str(item["country"]),
                country_code=str(item["country_code"]),
                city=str(item["city"]),
                region=str(item["region"]),
                hcloud_location=str(item["hcloud_location"]),
                public_ip=_PLACEHOLDER_PUBLIC_IP,
                endpoint=f"{_PLACEHOLDER_PUBLIC_IP}:{_PLACEHOLDER_WG_PORT}",
                wg_listen_port=_PLACEHOLDER_WG_PORT,
                wg_public_key=str(item["wg_public_key"]),
                wg_private_key_encrypted="bootstrap-placeholder",
                status="active",
                health_status="unknown",
                hcloud_server_state="running",
                priority_weight=100,
                tier_restriction=item["tier_restriction"],
            )
        )
        existing_ids.add(server_id)
        inserted += 1

    if inserted == 0:
        return

    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        logger.warning(
            "Default VPN server bootstrap hit an integrity conflict; leaving existing inventory untouched."
        )
