# UI Theme Refactor Changelog

Date: 2026-03-26

## Scope

- `securewave_app` Flutter frontend
- Website frontend in `static/` (HTML, CSS, JS)
- UI-only redesign pass with no backend or business-logic changes

## Design Direction

- Dark slate and black base surfaces
- Electric blue primary accent
- Neon pink and purple secondary accent
- Shared glass-panel treatment, luminous gradients, and tighter spacing rhythm
- Unified component language across Flutter and website

## Strict Color Transformation

- Applied a color-only stabilization pass across the existing Flutter and
  website UI without changing layout, spacing, typography, or interaction
  structure
- Locked remaining Flutter theme surfaces to the near-black stack
  `#0b0b0f`, `#111117`, and `#1a1a22`
- Kept the accent remap constrained to:
  - neon blue `#4cc9ff`
  - neon purple `#7a5cff`
  - neon pink `#ff2bd6`
- Updated remaining bright-accent foregrounds in Flutter onboarding/account
  surfaces so contrast stays correct on the strict dark palette
- Reconfirmed the website token layer keeps former white surfaces mapped to
  near-black panels rather than introducing new component patterns
- Replaced the last light toast/panel fallback in the shared website CSS with
  dark elevated surfaces so no white-backed runtime UI remains
- Reconfirmed the shared logo and favicon assets render on black foundations
  with blue/purple neon accents and no green variants

## Purple-Primary Inversion

- Inverted the accent hierarchy so purple is now the primary design color
  across both Flutter and website surfaces
- Kept blue as the secondary support accent for contrast, status support, and
  layered gradients
- Rebased the website token layer and shared Flutter token layer so primary
  buttons, focus states, panel glow, and hero emphasis resolve to purple first

## Color System Reset

- Replaced the previous dark-blue leaning base with a stricter near-black stack:
  - `#050508`
  - `#0b0b0f`
  - `#111117`
  - `#1a1a22`
- Locked the accent system to:
  - neon blue `#4cc9ff`
  - neon pink `#ff2bd6`
  - neon purple `#7a5cff`
- Removed the remaining first-party green visual accents from:
  - Flutter theme tokens
  - website token variables
  - status page indicator classes
  - logo and favicon SVG assets

## Audit Findings

- Flutter styling was split across multiple theme layers and widget-local overrides:
  - `ui/theme/app_theme.dart`
  - `ui/theme/securewave_theme.dart`
  - `ui/design/app_colors.dart`
  - screen-local gradients, status tones, and auth surfaces
- Website styling was split across:
  - `static/css/web_ui_v1.css`
  - `static/css/htb_theme.css`
  - repeated inline HTML styles
  - JS-driven `style.*` mutations
- Legacy green/cyan HTB visual remnants were still present beside the newer SecureWave palette
- Layout rhythm and panel treatment were inconsistent across auth, dashboard, connection, diagnostics, and account views

## Flutter Changes

- Added the centralized Flutter color source in `securewave_app/lib/core/theme/colors.dart`
- Rebased `securewave_app/lib/ui/design/app_colors.dart` onto that core token file so existing UI imports resolve to one palette definition
- Added the centralized Flutter theme entry point in `securewave_app/lib/core/theme/app_theme.dart`
- Kept Material 3 theme wiring in `securewave_app/lib/ui/theme/app_theme.dart`, but rebased its effective palette onto the shared SecureWave dark system
- Standardized the color model in:
  - `securewave_app/lib/ui/design/app_colors.dart`
  - `securewave_app/lib/ui/theme/app_colors.dart`
- Normalized shared component styling in:
  - `securewave_app/lib/features/auth/auth_widgets.dart`
  - `securewave_app/lib/ui/widgets/glass_panel.dart`
  - `securewave_app/lib/ui/widgets/brand_mark.dart`
  - `securewave_app/lib/ui/components/health_badge.dart`
- Refactored the requested target screens onto the new design system without changing logic:
  - `securewave_app/lib/ui/screens/home_screen.dart`
  - `securewave_app/lib/ui/screens/auth/login_screen.dart`
  - `securewave_app/lib/ui/screens/auth/register_screen.dart`
  - `securewave_app/lib/ui/screens/connection_screen.dart`
  - `securewave_app/lib/ui/screens/diagnostics_screen.dart`
  - `securewave_app/lib/ui/screens/account_screen.dart`
- Replaced remaining first-party literal widget colors outside theme/token directories with semantic theme colors

## Flutter UI Transformation

- Upgraded the shared glass surface primitive in `securewave_app/lib/ui/widgets/glass_panel.dart` so screens can opt into consistent neon glow, border, and gradient treatment without carrying local decoration logic
- Reworked the shared CTA system in `securewave_app/lib/ui/components/neon_button.dart` from flat fills to gradient neon buttons with stronger hover/press glow and full-width support
- Rebased the dark Material theme in `securewave_app/lib/ui/theme/app_theme.dart` so focus rings, chips, nav indicators, switches, and progress indicators use the same black / blue / pink / purple accent hierarchy
- Refactored the main shell navigation in `securewave_app/lib/ui/layout/adaptive_shell_scaffold.dart` to match the new active-state treatment
- Updated the target screens to the shared primitives and spacing rhythm:
  - `securewave_app/lib/ui/screens/home_screen.dart`
  - `securewave_app/lib/ui/screens/connection_screen.dart`
  - `securewave_app/lib/ui/screens/diagnostics_screen.dart`
  - `securewave_app/lib/ui/screens/account_screen.dart`
  - `securewave_app/lib/ui/screens/auth/login_screen.dart`
  - `securewave_app/lib/ui/screens/auth/register_screen.dart`
- Tightened auth support surfaces in `securewave_app/lib/features/auth/auth_widgets.dart`
- Refined the reactive health surface in `securewave_app/lib/ui/components/health_badge.dart` with clearer score emphasis, deeper metric cards, and shared neon action buttons

## Website Changes

- Added the centralized website token layer in `static/css/theme_tokens.css`
- Reset the website variable palette to the new black / blue / pink / purple system
- Rebuilt `static/css/htb_theme.css` around the dark SecureWave redesign rather than the old green-first override
- Rebased `static/css/web_ui_v1.css` onto shared CSS variables so page components inherit one palette and spacing system
- Updated all first-party static pages to use the current cache-busted CSS assets
- Removed first-party inline styling from HTML and replaced it with reusable theme classes
- Renamed the status-page operational indicator class from green-based naming to neutral online-state naming
- Replaced JS visual mutations with class toggles and shared state classes in:
  - `static/js/auth.js`
  - `static/js/billing_center.js`
  - `static/js/dashboard.js`
  - `static/js/device_center.js`
  - `static/js/diagnostics_center.js`
  - `static/js/downloads.js`
  - `static/js/settings_center.js`

## Website Visual Reset

- Reworked the shared website structure layer in `static/css/web_ui_v1.css` so nav menus, buttons, forms, cards, CTA banners, modals, and pricing surfaces default to dark glass instead of white or flat blue treatments
- Tightened `static/css/htb_theme.css` into a black-first neon override with subtler page glows and stronger pink / purple / blue emphasis on hero, navigation, and interactive states
- Updated the homepage and pricing surfaces through shared selectors instead of page-local overrides, including:
  - hero glow composition
  - pricing-card featured treatment
  - CTA banner contrast
  - navbar hover states
  - button hover lift and glow
- Bumped the cache-busted CSS asset references across all first-party `static/*.html` pages so the redesigned website assets are fetched immediately

## Final Consistency Pass

- Normalized the Flutter token vocabulary so shared UI code now refers to primary / secondary accent tokens instead of the older green / cyan naming, while keeping the rendered palette unchanged
- Removed the last first-party legacy accent wording from shared Flutter component docs and status helpers to keep the design system language aligned with the actual black / blue / pink / purple palette
- Tightened the website base mobile-nav hover state in `static/css/web_ui_v1.css` so the fallback structural CSS now matches the neon hover treatment already used by the branded override layer
- Re-ran first-party scans for legacy accent identifiers and stale website hover styles before the final validation loop

## Component Standardization

- Buttons now follow one primary blue-to-pink/purple accent language
- Cards and panels now use the same glass surface, border, radius, and shadow treatment
- Status and health surfaces now use semantic tokens instead of one-off tones
- Auth layouts, dashboard metrics, connection summaries, and diagnostics panels now share the same spacing and typography rhythm
- Brand assets now render with black foundations and pink / purple / blue accents rather than green / cyan mixes

## Deduplication

- Removed raw first-party HTML inline styles from website pages
- Removed first-party website JS `style.*` mutations
- Removed remaining first-party literal Flutter `Color(0x...)` usage outside theme/token directories
- Consolidated repeated visual mappings for:
  - connection state gradients
  - auth hero/header treatment
  - badge and panel tones
  - background glow layers

## Branding Cleanup

- Unified the primary SecureWave shield asset across Flutter and website runtime surfaces
- Reworked the logo mark to use a pink -> purple -> blue neon wave treatment on near-black foundations
- Replaced plain white wordmark rendering with shared gradient branding for Flutter and website navigation/footer brand rows
- Standardized website favicon usage onto `/favicon.svg` instead of pointing favicon tags at the navbar logo path
- Kept legacy duplicate logo variants removed so runtime surfaces resolve to one active mark family

## Validation

- Flutter:
  - `flutter analyze` passed
  - `flutter test` passed
- Website:
  - `pytest -q tests/web_smoke/test_device_center_security.py tests/web_smoke/test_web_account_center.py tests/unit/test_ui_pages.py` passed
  - `pytest -q tests/preview/test_assets_loaded.py tests/preview/test_http_status.py` passed

## Notes

- This pass intentionally avoided backend changes and business-logic changes
- Earlier runs showed intermittent environment-sensitive validation noise in:
  - the Flutter cold-start performance benchmark
  - the preview-stack startup fixture
- Final validation on the current code passed
