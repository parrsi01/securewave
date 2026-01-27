# SecureWave VPN - Design System v1.0

Last Updated: 2026-03-01
Version: 1.0.0
Status: Active

## Overview

SecureWave v1.0 is a calm, trustworthy, app-first design system for non-technical users. It prioritizes clarity, generous spacing, and a friendly, professional tone.

Design principles:
- Calm and steady visual language
- App-first guidance with clear primary actions
- Accessible layouts with readable type
- Consistent, simple component rules

## 1. Color System

Palette: Calm Tide

| Token | Hex | Usage |
| --- | --- | --- |
| Background | #F5F7FB | Page backgrounds |
| Background Strong | #E7EDF3 | Section accents |
| Surface | #FFFFFF | Cards and panels |
| Surface Muted | #F0F4F7 | Soft blocks |
| Accent | #1B6B68 | Primary CTAs, highlights |
| Accent Strong | #0F4F4C | Primary contrast |
| Accent Soft | #D5EFEC | Pills and badges |
| Sun Accent | #F6C14D | Warm highlights |
| Success | #1F8F5C | Success states |
| Warning | #C26B1F | Warning states |
| Ink | #0B1F2A | Headings, primary text |
| Ink Muted | #4A5B66 | Body text |
| Ink Soft | #72838F | Supporting text |
| Border | #D7E0E7 | Dividers and borders |

CSS variables:
```
:root {
  --bg: #f5f7fb;
  --bg-strong: #e7edf3;
  --surface: #ffffff;
  --surface-muted: #f0f4f7;
  --accent: #1b6b68;
  --accent-strong: #0f4f4c;
  --accent-soft: #d5efec;
  --accent-sun: #f6c14d;
  --success: #1f8f5c;
  --warning: #c26b1f;
  --ink: #0b1f2a;
  --ink-muted: #4a5b66;
  --ink-soft: #72838f;
  --border: #d7e0e7;
}
```

Flutter constants:
```
static const Color background = Color(0xFFF5F7FB);
static const Color backgroundStrong = Color(0xFFE7EDF3);
static const Color surface = Color(0xFFFFFFFF);
static const Color surfaceMuted = Color(0xFFF0F4F7);
static const Color accent = Color(0xFF1B6B68);
static const Color accentStrong = Color(0xFF0F4F4C);
static const Color accentSoft = Color(0xFFD5EFEC);
static const Color accentSun = Color(0xFFF6C14D);
static const Color success = Color(0xFF1F8F5C);
static const Color warning = Color(0xFFC26B1F);
static const Color ink = Color(0xFF0B1F2A);
static const Color inkMuted = Color(0xFF4A5B66);
static const Color inkSoft = Color(0xFF72838F);
static const Color border = Color(0xFFD7E0E7);
```

## 2. Typography

Single font family:
- Manrope

CSS:
```
--font-family: "Manrope", sans-serif;
```

Type scale:
- 14
- 16
- 18
- 22
- 28
- 36

## 3. Spacing Scale

Allowed spacing values:
- 4
- 8
- 12
- 16
- 24
- 32
- 48
- 64

## 4. Component Rules

Buttons:
- Height: 44 to 52
- Primary, secondary, ghost only
- Rounded pill shape

Inputs:
- Height: 44 to 52
- Labels above inputs
- Clear focus ring

Layout:
- Mobile-first from 320px
- Generous spacing to avoid dense text blocks
- No overlapping layers

## 5. Accessibility

- Minimum touch target: 44px
- Visible focus ring on all interactive elements
- Text contrast meets WCAG 2.1 AA

## 6. Motion

- Motion is minimal and functional
- Only subtle hover elevation and focus indicators
