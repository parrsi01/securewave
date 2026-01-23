# SecureWave VPN - Design System v5.0

**Last Updated:** 2026-01-23
**Version:** 5.0 (PrivadoVPN-Inspired Dark Theme)
**Status:** Production

---

## Overview

This document defines the visual design system for SecureWave VPN across both the website (HTML/CSS) and Flutter mobile/desktop app. The design philosophy emphasizes a **modern dark aesthetic** with vibrant accent colors, inspired by leading consumer VPN products like PrivadoVPN.

**Design Principles:**
- Dark-first: Elegant dark theme reduces eye strain and signals modern tech
- Vibrant accents: Orange and green provide clear visual hierarchy
- App-first hierarchy: Website is control panel, app handles VPN connection
- Mobile-first: Responsive design starting from 320px
- Accessibility: WCAG 2.1 AA compliant

---

## 1. Color System

### Primary Brand Colors

SecureWave uses a dark foundation with vibrant orange as the primary accent color.

```css
/* Dark Theme Backgrounds */
--bg-darkest: #080a0b   /* Deepest background */
--bg-dark: #1c1e22      /* Main background */
--bg-card: #25272d      /* Card surfaces */
--bg-card-hover: #30343b /* Card hover state */
--bg-elevated: #2d3038  /* Elevated elements */

/* Accent Orange (Primary) */
--accent-orange: #ff8f00        /* Main accent */
--accent-orange-dark: #f86605   /* Gradient end, hover */
--accent-orange-light: #ffb347  /* Light variant */

/* Accent Green (Success/Connected) */
--accent-green: #28d799         /* Connected state, success */
--accent-green-dark: #1fa87a    /* Gradient end, hover */
--accent-green-light: #5eedb8   /* Light variant */

/* Accent Purple (Tertiary) */
--accent-purple: #5058c8        /* Special elements */
--accent-purple-dark: #3a42b7   /* Hover */
```

**Flutter Constants:**
```dart
static const Color accentOrange = Color(0xFFFF8F00);
static const Color accentGreen = Color(0xFF28D799);
static const Color accentPurple = Color(0xFF5058C8);
```

---

### Semantic Colors

```css
--success: #28d799    /* Green - connected, success */
--success-bg: rgba(40, 215, 153, 0.15)
--warning: #f59e0b    /* Amber - warnings */
--warning-bg: rgba(245, 158, 11, 0.15)
--error: #ef4444      /* Red - errors, disconnected */
--error-bg: rgba(239, 68, 68, 0.15)
--info: #3b82f6       /* Blue - informational */
--info-bg: rgba(59, 130, 246, 0.15)
```

---

### Neutral Grays

```css
--gray-50:  #f1f2f4   /* Lightest */
--gray-100: #e0e2e6
--gray-200: #d4d6d7
--gray-300: #c1c5cd   /* Text secondary */
--gray-400: #93999c   /* Text tertiary */
--gray-500: #6b7280   /* Text muted */
--gray-600: #4b5563
--gray-700: #374151
--gray-800: #25272d   /* Card background */
--gray-900: #1c1e22   /* Main background */
```

---

### Text Colors

```css
/* Dark Theme */
--text-primary: #ffffff     /* White - headings, important */
--text-secondary: #c1c5cd   /* Light gray - body text */
--text-tertiary: #93999c    /* Medium gray - labels */
--text-muted: #6b7280       /* Dim gray - disabled */

/* Light Theme (via [data-theme="light"]) */
--text-primary: #0f172a     /* Near black */
--text-secondary: #334155   /* Dark gray */
--text-tertiary: #64748b    /* Medium gray */
--text-muted: #94a3b8       /* Light gray */
```

---

### Border Colors

```css
--border-primary: rgba(255, 255, 255, 0.08)   /* Subtle borders */
--border-secondary: rgba(255, 255, 255, 0.12) /* Visible borders */
--border-accent: rgba(255, 143, 0, 0.3)       /* Accent borders */
```

---

### Gradients

```css
/* Primary Actions */
--gradient-orange: linear-gradient(90deg, #ff8f00 0%, #f86605 100%);

/* Success States */
--gradient-green: linear-gradient(90deg, #28d799 0%, #1fa87a 100%);

/* Special Elements */
--gradient-purple: linear-gradient(90deg, #5058c8 0%, #3a42b7 100%);

/* Card Backgrounds */
--gradient-card: linear-gradient(180deg, #30343b 0%, #1c1e22 100%);

/* Hero Background Glow */
--gradient-hero: radial-gradient(ellipse at 50% 0%, rgba(255, 143, 0, 0.15) 0%, transparent 60%);
```

---

### Light Mode Override

The light theme is activated via `[data-theme="light"]` attribute on the root element.

```css
[data-theme="light"] {
  --bg-darkest: #f8fafc;
  --bg-dark: #ffffff;
  --bg-card: #ffffff;
  --bg-card-hover: #f1f5f9;
  --bg-elevated: #f8fafc;
  --text-primary: #0f172a;
  --text-secondary: #334155;
  --text-tertiary: #64748b;
  --border-primary: rgba(0, 0, 0, 0.08);
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
}
```

---

## 2. Typography

### Font Family

**Single Font System:** Inter (Google Fonts)

```css
--font-sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
```

**CDN Import:**
```html
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
```

**Flutter:**
```dart
GoogleFonts.interTextTheme()
```

---

### Type Scale

```css
--font-size-xs:   0.75rem    /* 12px */
--font-size-sm:   0.875rem   /* 14px */
--font-size-base: 1rem       /* 16px */
--font-size-lg:   1.125rem   /* 18px */
--font-size-xl:   1.25rem    /* 20px */
--font-size-2xl:  1.5rem     /* 24px */
--font-size-3xl:  1.875rem   /* 30px */
--font-size-4xl:  2.25rem    /* 36px */
--font-size-5xl:  3rem       /* 48px */
--font-size-6xl:  3.75rem    /* 60px */
```

---

### Font Weights

```css
--font-weight-normal:    400
--font-weight-medium:    500
--font-weight-semibold:  600
--font-weight-bold:      700
--font-weight-extrabold: 800
```

---

### Line Heights

```css
--line-height-tight:   1.25
--line-height-normal:  1.5
--line-height-relaxed: 1.7
```

---

## 3. Spacing Scale

```css
--space-1:  0.25rem   /* 4px */
--space-2:  0.5rem    /* 8px */
--space-3:  0.75rem   /* 12px */
--space-4:  1rem      /* 16px - DEFAULT */
--space-5:  1.25rem   /* 20px */
--space-6:  1.5rem    /* 24px */
--space-8:  2rem      /* 32px */
--space-10: 2.5rem    /* 40px */
--space-12: 3rem      /* 48px */
--space-16: 4rem      /* 64px */
--space-20: 5rem      /* 80px */
--space-24: 6rem      /* 96px */
```

---

## 4. Border Radius

```css
--radius-sm:   0.25rem   /* 4px */
--radius-md:   0.5rem    /* 8px */
--radius-lg:   0.75rem   /* 12px */
--radius-xl:   1rem      /* 16px */
--radius-2xl:  1.5rem    /* 24px */
--radius-3xl:  2rem      /* 32px */
--radius-full: 9999px    /* Pills, avatars */
```

---

## 5. Shadows

```css
/* Dark Theme Shadows */
--shadow-sm:  0 1px 2px rgba(0, 0, 0, 0.3)
--shadow-md:  0 4px 6px rgba(0, 0, 0, 0.4)
--shadow-lg:  0 13px 32px rgba(0, 0, 0, 0.59)
--shadow-xl:  0 16px 40px rgba(0, 0, 0, 0.41)

/* Glow Effects */
--shadow-glow-orange: 0 0 40px rgba(255, 143, 0, 0.3)
--shadow-glow-green: 0 0 40px rgba(40, 215, 153, 0.3)

/* Light Theme Shadows */
--shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05)
--shadow-md: 0 4px 6px rgba(0, 0, 0, 0.07)
--shadow-lg: 0 10px 20px rgba(147, 153, 156, 0.15)
```

---

## 6. Component Patterns

### Buttons

**Primary Button (Orange):**
```html
<button class="btn btn-primary">Download App</button>
```
```css
.btn-primary {
  background: var(--gradient-orange);
  color: white;
  padding: 0.75rem 1.5rem;
  border-radius: var(--radius-lg);
  font-weight: 600;
  transition: all var(--transition-base);
}
```

**Secondary Button (Green):**
```html
<button class="btn btn-secondary">Create Account</button>
```

**Ghost Button:**
```html
<button class="btn btn-ghost">Sign In</button>
```

---

### Cards

```html
<div class="dashboard-card">
  <div class="dashboard-card-header">
    <h3 class="dashboard-card-title">Card Title</h3>
  </div>
  <!-- content -->
</div>
```
```css
.dashboard-card {
  background: var(--bg-card);
  border-radius: var(--radius-2xl);
  border: 1px solid var(--border-primary);
  padding: var(--space-6);
}
```

---

### Status Indicators

```html
<span class="status-pill">Active</span>
```
```css
.status-pill {
  background: var(--success-bg);
  color: var(--accent-green);
  padding: 0.375rem 0.875rem;
  border-radius: 9999px;
  font-size: 0.875rem;
  font-weight: 600;
}
```

---

### VPN Status

```css
.vpn-status-indicator.connected {
  background: var(--success-bg);
  color: var(--accent-green);
}

.vpn-status-indicator.disconnected {
  background: rgba(239, 68, 68, 0.15);
  color: var(--error);
}
```

---

## 7. Logo & Branding

### Logo Files

| File | Purpose | Format |
|------|---------|--------|
| logo.svg | Full navigation logo | Shield + waves |
| logo-mark.svg | App icon, square | Shield only |
| logo-dark.svg | Dark backgrounds | Light variant |
| favicon.svg | Browser favicon | Simplified 16px |

### Logo Concept

The SecureWave logo is a **modern shield with signal waves**:
- Orange gradient shield (#FF8F00 to #F86605)
- White curved signal waves (3 levels)
- Center connection dot
- Represents secure, flowing data protection

### Logo Usage

```html
<!-- Navigation -->
<a href="/" class="navbar-brand">
  <img src="/img/logo.svg" alt="SecureWave" height="36">
  <span>SecureWave</span>
</a>
```

**Color Rules:**
- Logo primary: Orange gradient (#FF8F00)
- Logo on dark: Orange or white
- Logo on light: Orange or dark gray

---

## 8. Responsive Breakpoints

```css
/* Mobile First */
@media (min-width: 640px)  { /* sm - Large phones */ }
@media (min-width: 768px)  { /* md - Tablets */ }
@media (min-width: 1024px) { /* lg - Desktops */ }
@media (min-width: 1280px) { /* xl - Large desktops */ }
```

**Testing Requirements:**
- 320px (Small mobile)
- 768px (Tablet)
- 1024px (Desktop)
- 1280px (Large desktop)

---

## 9. Accessibility

### WCAG 2.1 AA Requirements

**Color Contrast Ratios:**
- Normal text: Minimum 4.5:1
- Large text: Minimum 3:1
- UI components: Minimum 3:1

**Verified Combinations:**
- White on `#1c1e22`: 14.7:1
- `#ff8f00` on `#080a0b`: 7.8:1
- `#28d799` on dark: 10.2:1

### Touch Targets
Minimum: 44px x 44px (iOS) / 48px x 48px (Android)

### Keyboard Navigation
- Skip links: `.skip-to-main`
- Focus states: Orange outline (3px)
- Tab order follows visual order

---

## 10. Theme Toggle

The website includes a light/dark mode toggle:

```html
<li class="theme-toggle">
  <button data-theme="light" aria-label="Light mode">
    <!-- Sun icon -->
  </button>
  <button data-theme="dark" aria-label="Dark mode">
    <!-- Moon icon -->
  </button>
</li>
```

Theme is persisted in `localStorage` and respects system preference.

---

## 11. Animation & Transitions

```css
--transition-fast: 150ms ease-in-out
--transition-base: 200ms ease-in-out
--transition-slow: 300ms ease

/* Loading spinner */
@keyframes spin {
  to { transform: rotate(360deg); }
}

/* Skeleton loading */
@keyframes skeleton {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
```

---

## 12. Version History

**v5.0 - PrivadoVPN-Inspired (2026-01-23)**
- Dark-first theme with orange/green accents
- Inspired by modern consumer VPN products
- Full light/dark mode toggle
- Comprehensive responsive design
- WCAG 2.1 AA accessibility compliance

**v4.1 - Deep Ocean (2026-01-23)**
- Attempted blue/slate redesign
- Not implemented (superseded by v5.0)

**v4.0 - Original Release**
- Initial design system
- Cyan/teal/amber palette
- Space Grotesk + Work Sans typography

---

## 13. Implementation Checklist

### Website (HTML/CSS)
- [x] Dark theme with orange/green accents
- [x] Inter font family
- [x] Modern logo (shield + waves)
- [x] Responsive navigation
- [x] Theme toggle (light/dark)
- [x] Mobile-first breakpoints
- [x] WCAG AA compliance
- [x] App download CTAs

### Flutter App (Dart)
- [x] Dark theme with orange/green accents
- [x] Light theme variant
- [x] GoogleFonts Inter
- [x] Material 3 compliance
- [x] Consistent color scheme
- [x] VPN status indicators

---

**End of Design System Documentation**
