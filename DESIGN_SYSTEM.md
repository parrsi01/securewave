# SecureWave VPN - Design System v5.1

**Last Updated:** 2026-01-23
**Version:** 5.1 (Lavender Light Theme)
**Status:** Production

---

## Overview

This document defines the visual design system for SecureWave VPN across both the website (HTML/CSS) and Flutter mobile/desktop app. The design philosophy emphasizes a **modern, calm, consumer-grade aesthetic** with a lavender color palette that communicates trust and security.

**Design Principles:**
- Light-first: Clean, calming lavender backgrounds
- Purple accents: Primary interactions use #A294F9
- App-first hierarchy: Website is control panel, app handles VPN connection
- Mobile-first: Responsive design starting from 320px
- Accessibility: WCAG 2.1 AA compliant

---

## 1. Color System

### Brand Palette (MANDATORY)

These four colors define the SecureWave brand identity:

| Token | Hex | Usage |
|-------|-----|-------|
| Background | `#F5EFFF` | Page backgrounds, scaffolds |
| Card/Surface | `#E5D9F2` | Cards, panels, inputs |
| Secondary | `#CDC1FF` | Subtle accents, hover states |
| Primary | `#A294F9` | CTAs, buttons, links, focus |

```css
/* CSS Variables */
--bg-darkest: #F5EFFF;
--bg-card: #E5D9F2;
--secondary: #CDC1FF;
--primary: #A294F9;
```

```dart
// Flutter Constants
static const Color bgLightest = Color(0xFFF5EFFF);
static const Color bgCard = Color(0xFFE5D9F2);
static const Color secondaryColor = Color(0xFFCDC1FF);
static const Color primaryColor = Color(0xFFA294F9);
```

---

### Primary Accent Variants

```css
--primary: #A294F9          /* Main accent */
--primary-dark: #8B7CF7     /* Hover/pressed states */
--primary-light: #B8ADF9    /* Light variant */
```

---

### Semantic Colors

```css
--success: #10B981    /* Green - connected, success */
--success-bg: rgba(16, 185, 129, 0.12)
--warning: #F59E0B    /* Amber - warnings */
--warning-bg: rgba(245, 158, 11, 0.12)
--error: #EF4444      /* Red - errors, disconnected */
--error-bg: rgba(239, 68, 68, 0.12)
--info: #3B82F6       /* Blue - informational */
--info-bg: rgba(59, 130, 246, 0.12)
```

---

### Text Colors

**Light Theme (Default):**
```css
--text-primary: #1F1F1F     /* Headings, important text */
--text-secondary: #4A4A4A   /* Body text */
--text-tertiary: #6B6B6B    /* Labels, captions */
--text-muted: #9CA3AF       /* Disabled, placeholder */
```

**Dark Theme:**
```css
--text-primary: #FFFFFF
--text-secondary: #D4D0DE
--text-tertiary: #9B95A8
--text-muted: #6B6578
```

---

### Border Colors

```css
--border-primary: rgba(162, 148, 249, 0.2)   /* Subtle borders */
--border-secondary: rgba(162, 148, 249, 0.35) /* Visible borders */
--border-accent: rgba(162, 148, 249, 0.5)     /* Focus, active */
```

---

### Gradients

```css
/* Primary Gradient (CTAs) */
--gradient-primary: linear-gradient(135deg, #A294F9 0%, #CDC1FF 100%);

/* Success Gradient */
--gradient-green: linear-gradient(135deg, #10B981 0%, #059669 100%);

/* Card Background */
--gradient-card: linear-gradient(180deg, #FFFFFF 0%, #F5EFFF 100%);

/* Hero Glow */
--gradient-hero: radial-gradient(ellipse at 50% 0%, rgba(162, 148, 249, 0.15) 0%, transparent 60%);
```

---

### Dark Mode

Dark mode is activated via `[data-theme="dark"]` on the root element.

```css
[data-theme="dark"] {
  --bg-darkest: #1A1625;
  --bg-dark: #241D30;
  --bg-card: #2D2540;
  --bg-elevated: #322A45;
  --text-primary: #FFFFFF;
  --text-secondary: #D4D0DE;
  --border-primary: rgba(205, 193, 255, 0.15);
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

8px base scale for consistent spacing:

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

**Light Theme:**
```css
--shadow-sm:  0 1px 2px rgba(162, 148, 249, 0.08)
--shadow-md:  0 4px 12px rgba(162, 148, 249, 0.12)
--shadow-lg:  0 8px 24px rgba(162, 148, 249, 0.16)
--shadow-xl:  0 16px 40px rgba(162, 148, 249, 0.2)
--shadow-glow-primary: 0 0 40px rgba(162, 148, 249, 0.35)
```

**Dark Theme:**
```css
--shadow-sm:  0 1px 2px rgba(0, 0, 0, 0.3)
--shadow-md:  0 4px 12px rgba(0, 0, 0, 0.4)
--shadow-lg:  0 8px 24px rgba(0, 0, 0, 0.5)
```

---

## 6. Component Patterns

### Buttons

**Primary Button:**
```html
<button class="btn btn-primary">Download App</button>
```
```css
.btn-primary {
  background: var(--gradient-primary);
  color: white;
  padding: 0.75rem 1.5rem;
  border-radius: var(--radius-lg);
  font-weight: 600;
}
```

**Secondary Button:**
```html
<button class="btn btn-secondary">Learn More</button>
```

**Ghost Button:**
```html
<button class="btn btn-ghost">Sign In</button>
```

---

### Cards

```html
<div class="card">
  <div class="card-header">
    <h3 class="card-title">Card Title</h3>
  </div>
  <!-- content -->
</div>
```
```css
.card {
  background: var(--bg-card);
  border-radius: var(--radius-2xl);
  border: 1px solid var(--border-primary);
  padding: var(--space-6);
}
```

---

### Status Indicators

```html
<span class="status-pill">Connected</span>
```
```css
.status-pill {
  background: var(--success-bg);
  color: var(--success);
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
  color: var(--success);
}

.vpn-status-indicator.disconnected {
  background: var(--error-bg);
  color: var(--error);
}
```

---

## 7. Logo & Branding

### Logo Files

| File | Purpose | Colors |
|------|---------|--------|
| logo.svg | Navigation logo | #A294F9 to #CDC1FF gradient |
| logo-mark.svg | App icon (square) | #A294F9 to #CDC1FF gradient |
| logo-dark.svg | Dark backgrounds | Same gradient |
| favicon.svg | Browser favicon | Simplified shield |

### Logo Concept

The SecureWave logo is a **modern shield with signal waves**:
- Purple gradient shield (#A294F9 to #CDC1FF)
- White curved signal waves (3 levels)
- Center connection dot
- Represents secure, flowing data protection

### Logo Usage

```html
<a href="/" class="navbar-brand">
  <img src="/img/logo.svg" alt="SecureWave" height="36">
  <span>SecureWave</span>
</a>
```

**Color Rules:**
- Logo on light: Use gradient (#A294F9)
- Logo on dark: Same gradient (high contrast)

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
- `#1F1F1F` on `#F5EFFF`: 12.8:1
- `#A294F9` on `#F5EFFF`: 3.2:1 (use for large text/icons only)
- White on `#A294F9`: 4.7:1

### Touch Targets
Minimum: 44px x 44px (iOS) / 48px x 48px (Android)

### Keyboard Navigation
- Skip links: `.skip-to-main`
- Focus states: Purple outline (3px)
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

/* Reduced motion */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## 12. Version History

**v5.1 - Lavender Light Theme (2026-01-23)**
- New brand palette: #F5EFFF, #E5D9F2, #CDC1FF, #A294F9
- Light-first design (calming lavender backgrounds)
- Purple primary accents
- Updated logo to match new palette
- Full light/dark mode support

**v5.0 - PrivadoVPN-Inspired (2026-01-23)**
- Dark theme with orange/green accents
- Superseded by v5.1

**v4.1 - Deep Ocean (2026-01-23)**
- Blue/slate palette (not deployed)

**v4.0 - Original Release**
- Cyan/teal/amber palette

---

## 13. Implementation Checklist

### Website (HTML/CSS)
- [x] Lavender brand palette applied
- [x] Inter font family
- [x] Modern logo (shield + waves in purple)
- [x] Responsive navigation
- [x] Theme toggle (light/dark)
- [x] Mobile-first breakpoints
- [x] WCAG AA compliance
- [x] App download CTAs

### Flutter App (Dart)
- [x] Lavender light theme (default)
- [x] Purple dark theme variant
- [x] GoogleFonts Inter
- [x] Material 3 compliance
- [x] Consistent color scheme
- [x] VPN status indicators

---

**End of Design System Documentation**
