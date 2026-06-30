TODO:
- Provision production SMTP/provider credentials, then run `scripts/release_go_no_go.sh --email-live-proof`.
- Run `scripts/stripe_billing_provision.py --confirm-live` with live Stripe keys, then run live billing proof.
- On a Mac, run `securewave_app/scripts/archive_ios_release.sh` with Apple signing assets to produce the final signed iOS archive/export.
- Create the App Store reviewer account after SMTP is live; do not submit placeholder review credentials.
- If App Store Connect asks for entitlement justification again, request NetworkExtension Packet Tunnel Provider only, not Hotspot Helper.
