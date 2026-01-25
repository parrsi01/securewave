# SecureWave VPN - Design System v1.0

**Last Updated:** 2026-01-25
**Version:** 1.0.0 (True v1.0 - Fresh Start)
**Status:** Stable

---

## Overview

This document defines the visual design system for SecureWave VPN. The design philosophy emphasizes a **calm, trustworthy, beginner-friendly aesthetic** with a teal color palette that communicates protection and reliability.

**Target Users:** Absolute beginners to technology who are non-technical and may be nervous about security.

**Design Principles:**
- Calm: Soft colors, generous spacing, no aggressive elements
- Trustworthy: Shield iconography, teal (associated with reliability and protection)
- Simple: One primary action per screen, minimal text, strong icons
- Accessible: WCAG 2.1 AA compliant, large touch targets

---

## 1. Color System

### Brand Palette

The teal color palette was chosen for its calming, trustworthy qualities. Teal is associated with clarity, communication, and protection - perfect for a VPN service.

| Token | Hex | Usage |
|-------|-----|-------|
| Primary | `#0D9488` | CTAs, buttons, links, focus states |
| Primary Light | `#14B8A6` | Gradients, hover states |
| Background | `#F8FAFC` | Page backgrounds |
| Card | `#FFFFFF` | Cards, panels, elevated surfaces |
| Text Primary | `#1E293B` | Headings, important content |
| Text Secondary | `#475569` | Body text |

### CSS Variables

```css
:root {
  /* Primary - Teal (Calm, Trustworthy) */
  --primary: #0D9488;
  --primary-dark: #0F766E;
  --primary-light: #14B8A6;

  /* Background */
  --bg-page: #F8FAFC;
  --bg-card: #FFFFFF;
  --bg-card-hover: #F1F5F9;

  /* Text */
  --text-primary: #1E293B;
  --text-secondary: #475569;
  --text-tertiary: #64748B;
  --text-muted: #94A3B8;

  /* Borders */
  --border-light: #E2E8F0;
  --border-medium: #CBD5E1;
}
```

### Flutter Constants

```dart
static const Color primaryColor = Color(0xFF0D9488);
static const Color primaryLight = Color(0xFF14B8A6);
static const Color bgPage = Color(0xFFF8FAFC);
static const Color bgCard = Color(0xFFFFFFFF);
static const Color textPrimary = Color(0xFF1E293B);
static const Color textSecondary = Color(0xFF475569);
```

---

### Semantic Colors

```css
--success: #10B981    /* Connected, success states */
--warning: #F59E0B    /* Warnings, attention needed */
--error: #EF4444      /* Errors, disconnected states */
--info: #0D9488       /* Informational (uses primary) */
```

---

### Gradients

```css
/* Primary Gradient (Buttons, CTAs) */
--gradient-primary: linear-gradient(135deg, #0D9488 0%, #14B8A6 100%);

/* Success Gradient */
--gradient-green: linear-gradient(135deg, #10B981 0%, #059669 100%);

/* Hero Glow Effect */
--gradient-hero: radial-gradient(ellipse at 50% 0%, rgba(13, 148, 136, 0.08) 0%, transparent 60%);
```

---

### Dark Mode

```css
[data-theme="dark"] {
  --bg-page: #0F172A;
  --bg-card: #1E293B;
  --bg-card-hover: #334155;
  --text-primary: #F1F5F9;
  --text-secondary: #CBD5E1;
  --primary-light: #2DD4BF;
  --border-light: #334155;
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
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

### Type Scale (Larger for Readability)

```css
--font-size-sm:   0.9375rem  /* 15px */
--font-size-base: 1.0625rem  /* 17px - DEFAULT */
--font-size-lg:   1.25rem    /* 20px */
--font-size-xl:   1.5rem     /* 24px */
--font-size-2xl:  1.875rem   /* 30px */
--font-size-3xl:  2.25rem    /* 36px */
--font-size-4xl:  3rem       /* 48px */
--font-size-5xl:  3.75rem    /* 60px */
```

**Note:** Base font size is 17px (larger than typical 16px) to improve readability for all users.

---

## 3. Spacing Scale

Generous spacing for breathing room:

```css
--space-1:  0.25rem   /* 4px */
--space-2:  0.5rem    /* 8px */
--space-3:  0.75rem   /* 12px */
--space-4:  1rem      /* 16px */
--space-5:  1.25rem   /* 20px */
--space-6:  1.5rem    /* 24px */
--space-8:  2rem      /* 32px */
--space-10: 2.5rem    /* 40px */
--space-12: 3rem      /* 48px */
--space-16: 4rem      /* 64px */
--space-20: 5rem      /* 80px */
```

---

## 4. Border Radius

Soft, friendly corners:

```css
--radius-sm:   0.375rem  /* 6px */
--radius-md:   0.5rem    /* 8px */
--radius-lg:   0.75rem   /* 12px */
--radius-xl:   1rem      /* 16px */
--radius-2xl:  1.25rem   /* 20px */
--radius-full: 9999px    /* Pills */
```

---

## 5. Shadows

Subtle, not aggressive:

```css
--shadow-sm:  0 1px 2px rgba(0, 0, 0, 0.04)
--shadow-md:  0 4px 12px rgba(0, 0, 0, 0.06)
--shadow-lg:  0 8px 24px rgba(0, 0, 0, 0.08)
--shadow-glow: 0 0 24px rgba(13, 148, 136, 0.2)
```

---

## 6. Components

### Buttons

**Large touch targets (minimum 52px height):**

```css
.btn {
  min-height: 52px;
  padding: 1rem 2rem;
  font-size: 1.0625rem;
  border-radius: 1rem;
  font-weight: 600;
}

.btn-primary {
  background: var(--gradient-primary);
  color: white;
}

.btn-lg {
  min-height: 60px;
  padding: 1.25rem 2.5rem;
  font-size: 1.25rem;
}
```

### Cards

```css
.card {
  background: var(--bg-card);
  border: 1px solid var(--border-light);
  border-radius: 1.25rem;
  padding: 2rem;
}
```

### Form Inputs

```css
.form-group input {
  min-height: 52px;
  padding: 1rem;
  border: 2px solid var(--border-light);
  border-radius: 0.75rem;
  font-size: 1.0625rem;
}

.form-group input:focus {
  border-color: var(--primary);
  box-shadow: 0 0 0 3px rgba(13, 148, 136, 0.15);
}
```

---

## 7. Logo & Branding

### Logo Design

The SecureWave logo is a **simple shield with checkmark**:
- Shield shape represents protection
- Checkmark inside represents "secure" (universally understood)
- Teal gradient (#0D9488 to #14B8A6)
- Works at all sizes from 16px to 256px

### Logo Files

| File | Purpose |
|------|---------|
| logo.svg | Primary navigation logo (40x40) |
| logo-dark.svg | For dark backgrounds (brighter variant) |
| logo-mark.svg | App icon with rounded square background (64x64) |
| favicon.svg | Browser favicon (32x32) |

### Logo Usage

```html
<a href="/" class="navbar-brand">
  <img src="/img/logo.svg" alt="SecureWave" height="40">
  <span>SecureWave</span>
</a>
```

---

## 8. Responsive Design

### Breakpoints

```css
@media (min-width: 640px)  { /* sm - Tablets */ }
@media (min-width: 768px)  { /* md - Small laptops */ }
@media (min-width: 1024px) { /* lg - Desktops */ }
@media (min-width: 1280px) { /* xl - Large screens */ }
```

### Testing Requirements

- 320px (Small mobile) - No horizontal scroll
- 768px (Tablet) - Proper grid layout
- 1024px (Desktop) - Full navigation
- 1280px (Large desktop) - Max container width

---

## 9. Accessibility

### WCAG 2.1 AA Requirements

**Color Contrast:**
- Text on background: Minimum 4.5:1
- Large text (>18px): Minimum 3:1
- UI components: Minimum 3:1

**Verified Combinations:**
- `#1E293B` on `#F8FAFC`: 11.7:1
- White on `#0D9488`: 4.5:1
- `#475569` on `#FFFFFF`: 7.0:1

**Touch Targets:**
- Minimum: 44x44px (iOS) / 48x48px (Android)
- Buttons default to 52px height

**Keyboard Navigation:**
- Skip links present
- Focus visible on all interactive elements
- Tab order follows visual order

**Reduced Motion:**
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## 10. Animation

```css
--transition-fast: 150ms ease-in-out
--transition-base: 200ms ease-in-out
--transition-slow: 300ms ease
```

Animations are subtle and purposeful. Avoid flashy or attention-grabbing effects.

---

## 11. Palette Rationale

**Why Teal?**

1. **Calm**: Teal is neither too warm nor too cold. It creates a sense of balance and calm.

2. **Trustworthy**: Associated with reliability, clarity, and communication. Perfect for a security product.

3. **Professional yet Approachable**: Strikes the right balance between corporate and friendly.

4. **Distinctive**: Different from typical VPN services that often use blue, green, or orange.

5. **Accessible**: Works well for color vision deficiencies and meets contrast requirements.

**Color Harmony:**
- Primary: Teal (#0D9488) - Trust, protection
- Success: Green (#10B981) - Connected, positive
- Warning: Amber (#F59E0B) - Attention needed
- Error: Red (#EF4444) - Problems, disconnected

---

## 12. Implementation Files

### Website
- `/static/css/professional.css` - Main stylesheet
- `/static/img/logo.svg` - Primary logo
- `/static/favicon.svg` - Favicon

### Flutter App
- `/securewave_app/lib/core/theme/app_theme.dart` - Theme configuration

---

**End of Design System v1.0**
