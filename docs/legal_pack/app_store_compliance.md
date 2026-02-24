# SecureWave — App Store Compliance Summary

**Version:** 4.0.0+1
**Prepared:** 2026-02-19
**Applies to:** Apple App Store · Google Play Store

---

## Apple App Store

### Applicable Guidelines

| Guideline | Requirement | Status |
|-----------|------------|--------|
| 1.4.1 — VPN & Device Management | App must use Network Extension framework; must only transmit data necessary to provide the service; must not collect user data without consent; must have a clear privacy policy | Compliant |
| 2.5.4 — VPN Apps | Must provide clear disclosure of what data is collected and how it's used | Compliant — Privacy Policy at `/privacy` |
| 3.1.1 — In-App Purchase | Subscription must use IAP for iOS in-app purchase flows, or WebKit for external checkout | [PLACEHOLDER — Confirm: subscription currently uses external web checkout. IAP integration required for App Store submission per guideline 3.1.1] |
| 4.2.2 — Minimum Functionality | App must provide a clearly defined use case | Compliant — primary function is VPN connectivity |
| 5.1.1 — Privacy Policy | Must have a linked, current privacy policy | Compliant |
| 5.1.2 — Permission Justifications | All entitlements must be justified | See Entitlements table below |

### Required Entitlements and Justifications

| Entitlement | Purpose | Usage String |
|-------------|---------|--------------|
| `com.apple.developer.networking.networkextension` (packet-tunnel-provider) | Required to create and manage a WireGuard VPN tunnel at the OS level | "SecureWave needs this entitlement to establish and manage your encrypted VPN tunnel using the system Network Extension framework." |
| `com.apple.security.network.client` | App must make outbound network connections to authenticate and fetch VPN configuration | — |

### App Privacy Nutrition Label (Data Used to Track You)

**None.** SecureWave does not track users across apps or websites.

### App Privacy Nutrition Label (Data Linked to You)

| Category | Data Type | Purpose |
|----------|-----------|---------|
| Contact Info | Email address | Account management |
| Financial Info | Purchase history (last 4 digits, card type) | Billing |

### App Privacy Nutrition Label (Data Not Linked to You)

| Category | Data Type | Purpose |
|----------|-----------|---------|
| Usage Data | Connection timestamps, bandwidth totals | Service operation (aggregated, purged within 24h) |
| Identifiers | Device OS version, app version | App analytics |

### App Review Notes

**What the app does:** Establishes an encrypted VPN tunnel using the iOS/macOS Network Extension packet tunnel framework. Users connect and disconnect via in-app controls. No VPN functionality operates in the background without user initiation.

**Test account required:** Yes. Provide a test account with an active subscription for reviewers. [PLACEHOLDER — insert test credentials in App Store Connect before submission]

**No special entitlement issues:** The app uses the `packet-tunnel-provider` extension, which requires the `com.apple.developer.networking.networkextension` entitlement. This is a standard entitlement for VPN apps and has been approved in principle.

**macOS status:** macOS VPN implementation is not complete in v4.0.0 and should not be submitted to the Mac App Store until the Network Extension is functional. See Known Issues.

### Known Issues (Must Resolve Before Submission)

1. **macOS VPN not implemented** — AppDelegate.swift contains a logging stub only. Network Extension entitlement is present in Release.entitlements but the VPN connection logic is not implemented. Do not submit macOS build to App Store.
2. **IAP integration** — If App Store distribution requires in-app purchase for subscriptions, Stripe web checkout must be replaced or supplemented with StoreKit.
3. **iOS minimum deployment target** — Confirm minimum is iOS 15.0 or higher for Network Extension compatibility.

---

## Google Play Store

### Applicable Policies

| Policy | Requirement | Status |
|--------|------------|--------|
| VPN Service Policy | App must register as a VPN app; must display a persistent VPN notification; must not route traffic without explicit user consent | Compliant — foreground service with notification |
| Permissions Policy | Must justify all dangerous and special permissions | See Permissions table below |
| Data Safety | Must accurately declare all data collected, shared, and security practices | See Data Safety table below |
| Subscription and Payments | Must use Google Play Billing for in-app subscriptions if distributed via Play Store | [PLACEHOLDER — Same concern as iOS: confirm whether Play Billing integration is required] |

### Permissions and Justifications

| Permission | Type | Justification |
|-----------|------|--------------|
| `BIND_VPN_SERVICE` | Special | Required to implement VPN service via Android VPN API |
| `FOREGROUND_SERVICE` | Normal | Required to maintain VPN connection in foreground with user-visible notification |
| `INTERNET` | Normal | Required to establish VPN tunnel and authenticate with backend |
| `RECEIVE_BOOT_COMPLETED` | Normal | Required for auto-connect feature if enabled by user |
| `ACCESS_NETWORK_STATE` | Normal | Required to detect connectivity changes and reconnect if needed |

**No dangerous permissions** beyond VPN service binding are requested.

### Data Safety Declaration

| Category | Data | Collected | Shared | Purpose |
|----------|------|-----------|--------|---------|
| Personal info | Email address | Yes | No | Account management |
| Financial info | Subscription status | Yes | No | Billing management |
| App activity | Connection timestamps, bandwidth totals | Yes | No | Service operation |
| Device or other IDs | App version, OS version | Yes | No | Crash/diagnostic reporting |

**Data encryption:** All data is encrypted in transit (TLS 1.3) and at rest (AES-256).
**Data deletion request:** Users can delete their account and all associated data via account settings or by contacting privacy@securewavevpn.com.

### Android-Specific Notes

- VPN service is implemented as a foreground service (`SecureWaveVpnService`) using WireGuard GoBackend
- VPN notification is persistent and user-dismissible only by disconnecting
- The app does not use accessibility services or device admin privileges
- The app targets API level 31+ with WireGuard native library

---

## Shared Requirements (Both Stores)

### Privacy Policy

URL: `https://securewavevpn.com/privacy`
Last updated: February 2026

The privacy policy must be accessible without authentication and must be linked from:
- App Store Connect (App Information)
- Play Console (Store Listing)
- In-app (Settings → Privacy Policy)
- App website footer

### Terms of Service

URL: `https://securewavevpn.com/terms`

### Support URL

URL: `https://securewavevpn.com/contact`

### Age Rating

Both stores: **17+** (Apple) / **PEGI 3 / Everyone** (Google) — No user-generated content, no violence, no adult content. [PLACEHOLDER — confirm rating category with store submissions]

### Content Advisory

SecureWave contains:
- No user-generated content
- No social features
- No advertising
- No third-party tracking SDKs

---

## Pre-Submission Checklist

- [ ] Privacy policy URL is live and accessible without authentication
- [ ] Terms of service URL is live
- [ ] Test account credentials are set up in App Store Connect / Play Console
- [ ] App Privacy Nutrition Label (iOS) is completed in App Store Connect
- [ ] Data Safety form (Android) is completed in Play Console
- [ ] IAP/Play Billing integration confirmed or external checkout exemption confirmed
- [ ] macOS submission deferred until Network Extension is implemented
- [ ] App version matches VERSION file (4.0.0)
- [ ] Screenshots and app preview videos prepared for all required device sizes
- [ ] Release notes / What's New text drafted
