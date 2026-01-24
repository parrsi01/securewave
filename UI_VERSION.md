# SecureWave VPN - UI Version

**Current Version:** 6.0
**Last Updated:** 2026-01-24
**Status:** STABLE (CI Passing)
**Deployment:** Pending Azure credentials configuration

---

## Version History

### v6.0 (2026-01-24) - Lavender Light Theme
- Complete brand refresh with lavender color palette
- Light-first design philosophy
- Improved CI/CD with UI-only change detection
- Responsive design verified at all breakpoints

**Brand Palette:**
- Background: #F5EFFF
- Card/Surface: #E5D9F2
- Secondary: #CDC1FF
- Primary: #A294F9

### v5.1 (2026-01-23) - Initial Lavender Implementation
- Transitioned from dark theme to light lavender theme
- Updated logos with purple gradient

### v5.0 (2026-01-23) - PrivadoVPN Inspired (Superseded)
- Dark theme with orange/green accents
- Replaced by v5.1

### v4.1 (2026-01-23) - Deep Ocean (Not Deployed)
- Blue/slate palette
- Superseded before production

### v4.0 (2026-01-22) - Original Refresh
- Cyan/teal/amber palette
- Initial modernization effort

---

## Design System

See [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md) for complete documentation.

---

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Website | STABLE | Azure App Service (pending deploy) |
| Flutter iOS | Development | Requires Xcode signing |
| Flutter Android | Development | Requires keystore |
| Flutter Desktop | Development | Linux/Windows/macOS |

---

## Stability Status

| Component | Status |
|-----------|--------|
| CI Pipeline | PASSING |
| Docker Build | PASSING |
| Lint Check | PASSING |
| UI Code | STABLE |
| Azure Deploy | Requires AZURE_CREDENTIALS secret |

---

## Visual Verification Checklist

- [x] 320px mobile - No horizontal scroll
- [x] 768px tablet - Proper grid layout
- [x] 1024px desktop - Full navigation
- [x] 1280px large desktop - Max container width
- [x] Light theme - Default experience
- [x] Dark theme - Toggle functionality
- [x] Logo scales 16px to 256px
- [x] WCAG 2.1 AA contrast compliance
