# Navy & silver UI restyle

Status: done (2026-11-25). Light/dark previews were rendered with a throwaway golden test that loads the bundled fonts, then deleted. The layout was probed at text scale 1×–3× on 320/360/412dp screens.

## Decisions (user-approved)
- Palette: deep navy + silver on cool white; light/dark follow the system.
- Home: grouped list (File & trang · Chỉnh sửa & ký · Chuyển đổi · Bảo mật & thông tin); a PRO tag replaces the lock icon.
- Font: Be Vietnam Pro only (400/500/600), bundled from google/fonts (OFL), works offline.

## Tokens
| Role | Light | Dark |
|---|---|---|
| primary / onPrimary | #14213D / #FFFFFF | #C9D4E8 / #0F1A2E |
| page (surface) | #F5F6F8 | #0C121D |
| card + hairline | #FFFFFF + #DFE3E9 | #121A27 + #263043 |
| text / secondary text | #141A24 / #5C6575 | #E5E8EE / #9AA3B2 |
| outline (inputs, ≥3:1 on page and fill) | #838C9C | #6B7586 |
| icon tiles (primaryContainer) | #E5EAF2 | #1F2C45 |

Radii: card 16, button/input 12, chip 10. Flat surfaces; only the app bar casts a faint shadow when content scrolls under it.

## Phases
1. [Restyle](phase-01-restyle.md): fonts, theme, shared widgets, home, Pro screen, screen touch-ups.

## Acceptance
- `flutter analyze --no-pub` reports 0 issues; `flutter test --no-pub` passes with the smoke test unchanged.
- No decorative hard-coded colours outside `lib/theme.dart`. The functional ones stay: the signature pad's paper and ink, and the redaction red.
- Light and dark previews reviewed (home, a tool screen, Pro, shared components).
- AGENTS.md and the README tree reflect `_groups`, `lib/theme.dart` and the bundled font.
