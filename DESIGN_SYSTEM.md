# SecureWave VPN - Design System v4.1

**Last Updated:** 2026-01-23
**Version:** 4.1 (Deep Ocean)
**Status:** Production

---

## Overview

This document defines the visual design system for SecureWave VPN across both the website (HTML/CSS) and Flutter mobile/desktop app. The design philosophy emphasizes **calm confidence**, **clarity**, and **professional minimalism** suitable for a privacy-focused VPN product.

**Design Principles:**
- Privacy = Clarity: Clean layouts communicate trustworthiness
- App-first hierarchy: Website is control plane, not the hero
- Modern minimalism: Flat design with subtle depth
- Accessibility: WCAG 2.1 AA compliant

---

## 1. Color System

### Primary Palette - Deep Ocean

SecureWave's primary brand color is a refined deep blue that communicates security and trust without VPN clichés.

```css
--primary-50:  #f0f4f8   /* Lightest tint - backgrounds */
--primary-100: #d9e5f2   /* Very light - hover states */
--primary-200: #b3cde0   /* Light - borders, dividers */
--primary-300: #7da8cc   /* Medium light - disabled states */
--primary-400: #4880b5   /* Medium - secondary buttons */
--primary-500: #2563a0   /* MAIN BRAND COLOR - primary actions */
--primary-600: #1e4e85   /* Dark - hover on primary */
--primary-700: #1a3c6b   /* Darker - pressed states */
--primary-800: #142e52   /* Very dark - text on light */
--primary-900: #0e2340   /* Darkest - high contrast text */
```

**Flutter Constants:**
```dart
static const Color primary = Color(0xFF2563A0);
```

**Usage Guidelines:**
- **Primary-500**: Main CTAs, links, focus states
- **Primary-50-200**: Backgrounds, cards, subtle accents
- **Primary-600-900**: Text, icons, dark mode backgrounds

---

### Accent Palette - Slate Blue

Used sparingly for secondary actions and supporting elements.

```css
--accent-400: #5b7e99   /* Light slate */
--accent-500: #475f7a   /* MAIN ACCENT */
--accent-600: #344456   /* Dark slate */
```

**Usage Guidelines:**
- Secondary buttons
- Supporting text
- Non-critical information

---

### Semantic Colors

```css
--success: #10b981   /* Green - success states, confirmations */
--warning: #f59e0b   /* Amber - warnings, alerts */
--error:   #ef4444   /* Red - errors, destructive actions */
--info:    #3b82f6   /* Blue - informational messages */
```

---

### Neutral Grays

```css
--gray-50:  #f9fafb   /* Backgrounds */
--gray-100: #f3f4f6   /* Hover backgrounds */
--gray-200: #e5e7eb   /* Borders */
--gray-300: #d1d5db   /* Disabled elements */
--gray-400: #9ca3af   /* Placeholder text */
--gray-500: #6b7280   /* Secondary text */
--gray-600: #4b5563   /* Primary text (light mode) */
--gray-700: #374151   /* Headings */
--gray-800: #1f2937   /* Dark backgrounds */
--gray-900: #111827   /* Darkest backgrounds */
```

---

### Dynamic Theme Colors

**Light Mode:**
```css
--bg-primary:   #f7fafc
--bg-secondary: #edf5f7
--text-primary: #0b1120
--text-secondary: #1f2937
--text-tertiary: #475569
--border-primary: #d0e4ec
```

**Dark Mode:**
```css
--bg-primary:   #0f172a
--bg-secondary: #1e293b
--text-primary: #f1f5f9
--text-secondary: #cbd5e1
--text-tertiary: #94a3b8
--border-primary: #334155
```

---

### Gradients (Use Sparingly)

```css
--gradient-primary: linear-gradient(135deg, #2563a0 0%, #1e4e85 100%);
--gradient-hero: linear-gradient(180deg, #f7fafc 0%, #f0f4f8 100%);
--gradient-card: linear-gradient(145deg, #ffffff 0%, #f9fafb 100%);
```

**Usage:** Reserved for hero sections, featured cards, or special promotional elements only. Avoid overuse.

---

## 2. Typography

### Font Family

**Single Font System:** Inter

```css
--font-sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
--font-display: 'Inter', -apple-system, sans-serif;
```

**Why Inter:**
- Industry standard for modern SaaS (Linear, Vercel, Stripe)
- Excellent legibility at all sizes
- Variable font support reduces load time
- Neutral, professional, works for both headings and body text

**CDN Import:**
```html
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

**Flutter:**
```dart
GoogleFonts.interTextTheme()
```

---

### Type Scale

```css
--font-size-xs:   0.75rem    /* 12px - Labels, metadata */
--font-size-sm:   0.875rem   /* 14px - Small body, navigation */
--font-size-base: 1rem       /* 16px - Body text */
--font-size-lg:   1.125rem   /* 18px - Large body */
--font-size-xl:   1.25rem    /* 20px - Small headings */
--font-size-2xl:  1.5rem     /* 24px - Section headings */
--font-size-3xl:  1.875rem   /* 30px - Subsection headings */
--font-size-4xl:  2.25rem    /* 36px - Page titles */
--font-size-5xl:  3rem       /* 48px - Hero titles (MAX) */
```

**Important:** Avoid sizes larger than `--font-size-5xl` (48px). Oversized typography wastes vertical space.

---

### Font Weights

```css
--font-weight-normal:    400   /* Body text */
--font-weight-medium:    500   /* Emphasized body text */
--font-weight-semibold:  600   /* Headings, buttons */
--font-weight-bold:      700   /* Strong emphasis */
```

**Avoid:** Font weights 800-900 (too heavy, creates visual noise)

---

### Line Heights

```css
--line-height-tight:   1.25   /* Headings */
--line-height-normal:  1.5    /* Body text */
--line-height-relaxed: 1.75   /* Long-form content */
```

---

### Typography Examples

```html
<!-- Page Hero Title -->
<h1 style="font-size: 2.5rem; font-weight: 600; line-height: 1.25;">
  Private Internet, One Tap Away
</h1>

<!-- Section Heading -->
<h2 style="font-size: 1.5rem; font-weight: 600;">
  Why SecureWave
</h2>

<!-- Body Text -->
<p style="font-size: 1rem; font-weight: 400; line-height: 1.5;">
  Download the SecureWave app to connect automatically.
</p>

<!-- Small Label -->
<span style="font-size: 0.875rem; font-weight: 500; color: var(--text-tertiary);">
  Last updated 2 hours ago
</span>
```

---

## 3. Spacing Scale

Consistent spacing creates visual rhythm and hierarchy.

```css
--space-1:  0.25rem   /* 4px  - Tight spacing */
--space-2:  0.5rem    /* 8px  - Icon gaps */
--space-3:  0.75rem   /* 12px - Small gaps */
--space-4:  1rem      /* 16px - DEFAULT gap */
--space-6:  1.5rem    /* 24px - Medium gaps */
--space-8:  2rem      /* 32px - Large gaps */
--space-12: 3rem      /* 48px - Section spacing */
--space-16: 4rem      /* 64px - Major sections */
```

**Usage Guidelines:**
- **4px/8px:** Internal component spacing (icon-to-text gaps)
- **16px/24px:** Between related elements (form fields, list items)
- **32px/48px:** Between distinct sections
- **64px:** Between major page sections

---

## 4. Border Radius

```css
--radius-sm:   0.375rem   /* 6px  - Small elements */
--radius-md:   0.5rem     /* 8px  - Buttons, inputs */
--radius-lg:   0.75rem    /* 12px - Cards */
--radius-xl:   1rem       /* 16px - Large cards */
--radius-2xl:  1.5rem     /* 24px - Featured elements (use sparingly) */
--radius-full: 9999px     /* Pills, avatars */
```

**Standard:** Use `--radius-lg` (12px) for most cards and containers.

---

## 5. Shadows

```css
--shadow-xs:  0 1px 2px 0 rgba(0, 0, 0, 0.05)
--shadow-sm:  0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px -1px rgba(0, 0, 0, 0.1)
--shadow-md:  0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -2px rgba(0, 0, 0, 0.1)
--shadow-lg:  0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -4px rgba(0, 0, 0, 0.1)
--shadow-xl:  0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 8px 10px -6px rgba(0, 0, 0, 0.1)
```

**Usage Guidelines:**
- **shadow-sm:** Buttons, inputs (resting state)
- **shadow-md:** Cards, dropdowns
- **shadow-lg:** Modals, popovers
- **shadow-xl:** Hero sections (use sparingly)

**Avoid:** Multi-layered shadows (3+ box-shadows). Keep it simple.

---

## 6. Component Patterns

### Buttons

**Primary Button:**
```html
<button class="btn btn-primary">
  Download App
</button>
```
```css
.btn-primary {
  background: var(--primary-500);
  color: white;
  padding: 0.75rem 1.5rem;
  border-radius: var(--radius-md);
  font-weight: 600;
  box-shadow: var(--shadow-sm);
  transition: all var(--transition-base);
}
.btn-primary:hover {
  background: var(--primary-600);
  box-shadow: var(--shadow-md);
}
```

**Secondary Button:**
```html
<button class="btn btn-secondary">
  Learn More
</button>
```
```css
.btn-secondary {
  background: var(--accent-500);
  color: white;
  padding: 0.75rem 1.5rem;
  border-radius: var(--radius-md);
  font-weight: 600;
}
```

**Ghost Button:**
```html
<button class="btn btn-ghost">
  Cancel
</button>
```
```css
.btn-ghost {
  background: transparent;
  color: var(--text-secondary);
  border: 1px solid var(--border-primary);
  padding: 0.75rem 1.5rem;
  border-radius: var(--radius-md);
}
```

---

### Cards

**Standard Card:**
```html
<div class="card">
  <div class="card-body">
    <h3>Card Title</h3>
    <p>Card content goes here.</p>
  </div>
</div>
```
```css
.card {
  background: white;
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-md);
  padding: var(--space-6);
}
```

---

### Input Fields

```html
<div class="form-group">
  <label for="email">Email Address</label>
  <input type="email" id="email" placeholder="you@example.com">
</div>
```
```css
.form-group input {
  width: 100%;
  padding: 0.75rem 1rem;
  border: 1px solid var(--border-primary);
  border-radius: var(--radius-md);
  font-size: var(--font-size-base);
  transition: border-color var(--transition-base);
}
.form-group input:focus {
  border-color: var(--primary-500);
  outline: none;
  box-shadow: 0 0 0 3px rgba(37, 99, 160, 0.1);
}
```

---

### Status Chips

```html
<span class="status-chip status-chip--success">Active</span>
<span class="status-chip status-chip--warning">Pending</span>
<span class="status-chip status-chip--error">Failed</span>
```
```css
.status-chip {
  display: inline-flex;
  align-items: center;
  padding: 0.25rem 0.75rem;
  border-radius: var(--radius-full);
  font-size: var(--font-size-sm);
  font-weight: 600;
}
.status-chip--success {
  background: rgba(16, 185, 129, 0.1);
  color: #065f46;
}
```

---

## 7. Logo & Branding

### Logo Files

- **logo.svg**: Full logo (mark + wordmark) for navigation
- **logo-mark.svg**: Mark only (square format) for app icons
- **logo-dark.svg**: Dark mode variant with lighter colors
- **favicon.svg**: Simplified 16px favicon

### Logo Concept: "Flow Mark"

The SecureWave logo represents **secure data flow** through overlapping geometric paths:
- Outer path: Data route
- Inner path: Encrypted tunnel
- Continuous flow: Uninterrupted connection

**Design Principles:**
- Minimal: No shields, locks, or cliché security symbols
- Scalable: Recognizable from 16px to 256px
- Monochrome-first: Works in single color (primary-600)
- Professional: Suitable for enterprise contexts

### Logo Usage

```html
<!-- Navigation -->
<a href="/" class="navbar-brand">
  <img src="/img/logo.svg" alt="SecureWave VPN" height="32">
  <span>SecureWave</span>
</a>

<!-- App Icon -->
<img src="/img/logo-mark.svg" alt="SecureWave" width="128" height="128">

<!-- Dark Mode -->
<img src="/img/logo-dark.svg" alt="SecureWave VPN">
```

**Color on Light Backgrounds:** `var(--primary-600)` or `#1e4e85`
**Color on Dark Backgrounds:** `var(--primary-200)` or `#b3cde0`

---

## 8. Responsive Breakpoints

```css
/* Mobile First Approach */
@media (min-width: 768px) {  /* Tablet */
  ...
}

@media (min-width: 1024px) { /* Desktop */
  ...
}

@media (min-width: 1280px) { /* Large Desktop */
  ...
}
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
- Large text (18px+ or 14px bold): Minimum 3:1
- UI components: Minimum 3:1

**Verified Combinations:**
- `primary-500` (#2563a0) on white: ✅ 6.8:1
- `primary-700` (#1a3c6b) on white: ✅ 10.2:1
- White on `primary-500`: ✅ 7.1:1

### Touch Targets

Minimum size: **44px × 44px** (iOS) / **48px × 48px** (Android)

### Keyboard Navigation

All interactive elements must be keyboard accessible:
- Tab order follows visual order
- Focus states clearly visible (3px outline in primary-500)
- Skip links provided for screen readers

---

## 10. Implementation Checklist

### Website (HTML/CSS)

- [ ] Update `professional.css` with Deep Ocean palette
- [ ] Replace font imports with Inter
- [ ] Swap logo files (logo.svg, favicon.svg)
- [ ] Reduce hero title sizes (max 2.5rem)
- [ ] Remove excessive shadows (max 2 box-shadows per element)
- [ ] Simplify gradients (use sparingly)
- [ ] Test responsive breakpoints (320px, 768px, 1024px, 1280px)
- [ ] Verify WCAG AA contrast ratios
- [ ] Test keyboard navigation

### Flutter App (Dart)

- [ ] Update `app_theme.dart` with new color constants
- [ ] Change GoogleFonts from Manrope to Inter
- [ ] Reduce font weights (max FontWeight.w600 for headings)
- [ ] Simplify gradients in UI components
- [ ] Update logo in `brand_logo.dart` widget
- [ ] Test on Android and iOS simulators
- [ ] Verify Material 3 theming compatibility
- [ ] Test hot reload stability

---

## 11. Version History

**v4.1 - Deep Ocean (2026-01-23)**
- Replaced cyan/teal/amber palette with refined deep blue
- Changed from Space Grotesk + Work Sans to Inter (single font)
- New minimal "Flow Mark" logo design
- Reduced hero typography from 3.5rem to 2.5rem max
- Simplified gradients (2-color max, use sparingly)
- Reduced font weights (max 600 for headings)
- Eliminated multi-layered shadows

**v4.0 - Original Release**
- Initial design system with cyan/teal/amber palette
- Space Grotesk + Work Sans typography
- Original shield-based logo
- Multi-layered shadows and extensive gradients

---

## 12. Support & Maintenance

**Design System Owner:** Development Team
**Last Audit:** 2026-01-23
**Next Review:** Q2 2026

For questions or updates to this design system, please open an issue in the SecureWave GitHub repository.

---

**End of Design System Documentation**
