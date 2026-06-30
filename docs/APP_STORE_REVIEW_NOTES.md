# App Store Review Notes

## Test Account (Placeholder)
- Email: REPLACE_WITH_TEST_EMAIL
- Password: REPLACE_WITH_TEST_PASSWORD
- 2FA: Disabled for review (enable only if requested by Apple)

## How to Test VPN Connection
1. Sign in with the test account in the SecureWave app.
2. Tap **Connect** to establish a tunnel.
3. Confirm status changes to “Connected” in the app UI.
4. Disconnect to end the tunnel.

## What the App Does
- The SecureWave app establishes the VPN tunnel on the user’s device using Apple Network Extension (Packet Tunnel).
- Users explicitly initiate and stop the tunnel in-app.
- App bundle ID: `com.securewave.vpn`
- Packet Tunnel extension bundle ID: `com.securewave.vpn.PacketTunnel`
- SecureWave does not use Hotspot Helper and does not authenticate captive Wi-Fi networks.

## What the Website Does
- The website manages accounts, subscriptions, and device configuration.
- The website does **not** establish VPN tunnels or route traffic in the browser.
- Apple review page: `https://securewaveapp.com/apple-review.html`
- Downloads page: `https://securewaveapp.com/download.html`

## Additional Notes
- Privacy Policy: `https://securewaveapp.com/privacy.html`
- Terms: `https://securewaveapp.com/terms.html`
- Support: `https://securewaveapp.com/contact.html`
- Ensure `AUTH_ENCRYPTION_KEY`, token secrets, and payment provider keys are set in production.
