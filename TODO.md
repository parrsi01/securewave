TODO:
- Provision production SMTP/provider credentials, then run `scripts/release_go_no_go.sh --email-live-proof`.
- Run `scripts/stripe_billing_provision.py --confirm-live` with live Stripe keys, then run live billing proof.
- Add Apple signing secrets to GitHub or run `securewave_app/scripts/archive_ios_release.sh` on a Mac with Apple signing assets to produce the final signed iOS archive/export.
- Produce and publish the Intel macOS UI demo zip if Intel Mac download support is required; the Apple Silicon macOS UI demo zip is already published.
- Create the App Store reviewer account after SMTP is live; do not submit placeholder review credentials.
- If App Store Connect asks for entitlement justification again, request NetworkExtension Packet Tunnel Provider only, not Hotspot Helper.
