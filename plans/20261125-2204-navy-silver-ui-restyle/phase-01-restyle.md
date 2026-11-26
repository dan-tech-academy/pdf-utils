# Phase 01: restyle

## Files
- Add: `assets/fonts/BeVietnamPro-{Regular,Medium,SemiBold}.ttf`, `assets/fonts/OFL.txt`, `lib/theme.dart`.
- Modify: `pubspec.yaml` (fonts), `lib/main.dart`, `lib/widgets.dart`, `lib/home_screen.dart`, `lib/screens/pro_screen.dart`, `PickTile` call sites (outlined icons), the stamp/sign/ocr touch-ups, `AGENTS.md`, `README.md`.

## Steps
1. Bundle the fonts and declare the family `BeVietnamPro`.
2. In `lib/theme.dart`, build `AppTheme.light`/`dark`: explicit ColorScheme, text theme and component themes. Use the `*ThemeData` classes, because Flutter 3.47 deprecates the old theme classes.
3. Shared widgets: `IconTile`; flat `PickTile`, `ResultCard` and `ErrorBanner`; a text-only `RunButton`.
4. Home: `_groups` of `_Tool`, built eagerly in a Column so the smoke test still finds titles below the fold. Add the PRO tag and the outputs card.
5. Pro screen: a hero section and a feature card. Keep `_ProFeature` and the hard-coded "7".
6. Verify with analyze, tests and the light/dark previews, then revert the xcconfig noise.

## Risks
- A lazy list on home would break the smoke test, so keep the eager build.
- Only weights 400/500/600 are bundled, so w700 resolves to 600.
- Rollback: revert the commit. No logic or data changes.
