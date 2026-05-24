# SecureWave App Process Overview

This folder explains how the SecureWave app works for a non-engineering reader.
It avoids GitHub terminology where possible.

## What Happens When Someone Opens The App

1. The Linux desktop starts one SecureWave window.
2. If the app is already open, the existing window is brought forward instead
   of starting a second copy.
3. The app loads its configuration and checks whether a saved login session
   exists.
4. If there is no saved session, the user sees Sign in / Create account.
5. After login, the app shows Connect, Servers, Account, and Settings.

## Main App Areas

- **Connect:** shows the current account, selected region, selected protocol,
  connection state, diagnostics, and usage.
- **Servers:** asks the backend for the verified server catalog and lets the
  user choose Auto-select or a specific available region.
- **Account:** shows the signed-in email, account status, and usage.
- **Settings:** shows runtime configuration, usage, diagnostics, portal link,
  and sign out.

## What The Backend Does

The backend is the online service at `https://api.securewaveapp.com/api`. It
handles registration, login, account lookups, usage totals, server catalog
loading, and VPN profile generation.

## What The VPN Runtime Does

When the user presses Connect, the app asks the backend for a real VPN profile.
The Linux runner then hands the profile to the relevant local tool:

- WireGuard uses `wg-quick`.
- OpenVPN uses `openvpn`.
- IKEv2 requires strongSwan tooling and is not counted as working until that
  path is verified end to end.

The app should show an error if a profile is missing, a tool is not installed,
permissions are missing, or the backend rejects the protocol.

## Current Truth For Review

- One app instance per Linux desktop session is the intended behavior.
- Live API mode is the default; mock/demo mode must be explicitly enabled.
- The production catalog hides placeholder region rows that point at the same
  Hetzner IP. This prevents the app from pretending to have more real regions
  than it has.
- The app must not show a connected state unless the native VPN path reports
  success.
