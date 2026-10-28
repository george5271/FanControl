# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos (native SwiftUI menu bar app; not in the web/ios/android set)

## Users
The author and Mac owners like them: someone on a MacBook Pro (tested on M1 Pro) who wants direct control over fan speed instead of macOS defaults. They open the panel from the menu bar for a few seconds, glance at temperature and RPM, and switch mode. (Inferred from README and code.)

## Product Purpose
Replace Macs Fan Control with a small menu bar utility offering three modes: Maximum, Off, and By temperature (stepped curve driven by the hottest CPU core). Success: the current state reads at a glance and changing mode takes one click.

## Operating Context
- Lives in the menu bar as a `MenuBarExtra` window; reopening the app shows the same panel in a regular window (notch fallback).
- Readings refresh every 2 s. A root LaunchDaemon helper performs SMC writes; without it fans cannot be controlled, and the UI must say so.
- Russian UI copy.

## Capabilities and Constraints
- Modes: Максимум, Выкл, По темп.; optional per-fan modes.
- Editable temperature steps (threshold °C → % of max RPM, 0 % = stop), hysteresis 3 °C.
- Settings: temperature/RPM in the menu bar, per-fan mode, launch at login, colour theme.
- macOS 13+, Swift 5.9, no third-party dependencies.

## Brand Commitments
- Visual references supplied by the user (2026-10-24): fintech balance widget in three colourways — deep blue, violet, light. Big rounded hero panel with a huge number, pill label, row of circular avatars overlapping the hero edge, a glass "last transaction" card, and a bottom row of glossy 3D circular and capsule buttons with a saturated primary. SF-style grotesk type, thin-line icons.
- Explicit request: remove the generic "AI" look of the previous magenta design.

## Evidence on Hand
Live sensor data only. No testimonials, metrics or claims to display.

## Product Principles
1. State first: temperature, RPM and active mode read in one glance.
2. One click to change mode; risky modes (Off) stay available but never prominent.
3. Never hide that the helper is missing — control silently failing is the worst outcome.
4. Native behaviour over decoration: keyboard shortcut, tooltips, macOS 13 compatibility.
