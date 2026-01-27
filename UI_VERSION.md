# SecureWave VPN - UI Version

Current Version: UI v1.0.0 — DEMO-STABLE
Last Updated: 2026-02-02
Status: DEMO-STABLE (UI v1.0.0)

---

## Version 1.0.0 (2026-02-02) - Locked Design System

This release establishes the deterministic UI v1.0 system for SecureWave.

### Brand Identity
- Logo: Abstract shield with wave motif
- Palette: Calm Marine (primary #1E3A5F, secondary #2C7A7B)
- Philosophy: Calm, trustworthy, beginner-friendly

### Color Palette
| Token | Hex | Purpose |
| --- | --- | --- |
| Primary | #1E3A5F | Navigation, CTAs |
| Secondary | #2C7A7B | Highlights, secondary actions |
| Background | #F4F7FA | Page background |
| Surface | #FFFFFF | Cards and panels |
| Success | #2F855A | Connected states |
| Error | #C53030 | Error states |

### Design Principles

Target users: absolute beginners to technology.

Principles:
1. Calm - Clear spacing, muted contrast
2. Trustworthy - Shield iconography, marine palette
3. Simple - One primary action per screen
4. Accessible - 48px minimum touch targets

---

## Platform Support

| Platform | Status | Notes |
| --- | --- | --- |
| Website | STABLE | Ready for deployment |
| Flutter Linux | STABLE | Desktop app |
| Flutter Android | Development | Requires keystore |
| Flutter iOS | Development | Requires Xcode signing |

---

## Files Modified

### Brand Assets
- `static/img/logo.svg`
- `static/favicon.svg`
- `securewave_app/assets/securewave_logo.svg`

### Stylesheets
- `static/css/ui_v1.css`

### Flutter Theme
- `securewave_app/lib/core/theme/app_ui_v1.dart`

### Documentation
- `DESIGN_SYSTEM.md`
- `UI_VERSION.md`

---

## Previous Versions (Superseded)

All previous UI variants are deprecated. UI v1.0 is the single source of truth.
