# AGENTS.md

Single-package Flutter app (Android + iOS) with no CI. It has 21 on-device PDF tools (14 free, 7 Pro via RevenueCat). PDF ops run on the Rust engine in `pdf_manipulator`.
User-facing text (UI, README, `Info.plist` usage strings) is hard-coded in Vietnamese, with no l10n. Code, identifiers and comments are in English.

## Verify

- Run `flutter pub get` once, then `flutter analyze --no-pub` → `flutter test --no-pub`. Local runs are the only gate. `--no-pub` matters: see the xcconfig note below.
- `flutter analyze` exits 1 even on infos. HEAD already has one (`use_null_aware_elements` in `lib/widgets.dart`), so it isn't yours.
- Don't run `dart format` over existing files. Most aren't format-clean, so it buries real diffs. Format only new files.
- `test/widget_test.dart` is the only test: a home-grid smoke test that checks several Vietnamese tool titles exactly.
- Engine ops run natively under plain `flutter test`, because the hook supplies a host binary. So test `PdfEngine` with `test()` and files in `Directory.systemTemp`. Don't use `outputFile()`/`outputsDir()` in tests: path_provider throws `MissingPluginException` there. Pickers, ML Kit and RevenueCat don't work in tests either.

## Toolchain gotchas

- Needs Flutter ≥3.47 / Dart ≥3.13.5. The deps are newer than most docs and examples (file_picker 13, share_plus 13, purchases_flutter 11, Material `RadioGroup`), so copy call patterns from `lib/files.dart`, `lib/widgets.dart`, `lib/pro.dart` and `screens/compress_screen.dart`. Deprecated APIs show up as infos, which fail analyze.
- `pdf_manipulator` is pinned to exactly `6.0.0`; keep it exact. Its native-assets hook downloads a prebuilt engine of about 25 MB into `.dart_tool/hooks_runner/`. That happens on the first build **and** the first `flutter test`, so both need network. Offline, or when you trim the engine through pubspec `hooks.user_defines` (`keep`, `build: size`), the hook compiles vendored Rust instead, which needs rustup.
- Any command that runs pub get (including analyze/test/run/build without `--no-pub`) adds a CocoaPods `#include?` line to the tracked `ios/Flutter/{Debug,Release}.xcconfig`. Keep that change out of unrelated commits by reverting it with `git checkout -- 'ios/Flutter/*.xcconfig'`. The quotes matter: unquoted, the glob also matches the untracked `Generated.xcconfig`, git fails and nothing gets reverted.

## Architecture

- `main.dart` → `HomeScreen` (`home_screen.dart`; its `_tools` list is the grid) → one StatefulWidget per tool in `lib/screens/`. State is plain `setState` plus singletons (`PdfEngine.instance`, `ProManager.instance`). There's no router or state-management package.
- Every PDF op goes through `PdfEngine` (`lib/engine.dart`). pdf_manipulator doesn't export `PdfDocument`/`PdfEditor`, so those types can't be named in fields, parameters or helpers. Keep `read`/`rewrite` callbacks inline in `PdfEngine` methods. Don't import `package:pdf_manipulator/src/...`, because it trips `implementation_imports`. `FileSource`, `FileSink` and `PdfFile` come from `package:pdf_manipulator/io.dart`, not the main barrel.
- Screen flow: `pickPdfs()`/`pickImages()` → `outputFile(base, ext)` (or `outputsDir()` for multi-file ops) → engine op → `RunningPane`/`ResultCard`/`ErrorBanner` from `lib/widgets.dart`. The home "File đã tạo" list shows only files directly in `<Documents>/pdf_utils/`. `outputFile()` strips non-ASCII, so filename suffixes are unaccented (`_nen`, `_cat`).
- Engine page indices are 0-based; the UI shows 1-based. `PdfRect` is in PDF points with y pointing up. Convert from widget/bitmap pixels the way `redact_screen.dart` `_run()` does.
- The Android-only MethodChannel `pdf_utils/content` (`readContentUri` in `MainActivity.kt`) backs `contentUriToFile()` for the scanner's `content://` results. On iOS, `contentUriToFile()` returns null.

## Adding or renaming a tool

1. Build the screen in `lib/screens/` with the flow above, then register it in `_tools` in `home_screen.dart`. List order is grid order.
2. Pro tool: set `isPro: true`. Gating happens only in `_openTool`; screens don't re-check. Also add a `_ProFeature` row in `screens/pro_screen.dart` and update its hard-coded "7".
3. Update the README counts, table and tree. Update `test/widget_test.dart` if a checked title changed.

## Pro / RevenueCat (`lib/pro.dart`)

- Keys: `flutter run --dart-define=RC_ANDROID_KEY=goog_… --dart-define=RC_IOS_KEY=appl_…`. `keysConfigured` needs **both** keys, even when you run on one platform. Otherwise Pro stays locked and the paywall shows a developer notice; nothing crashes.
- The README implies `kProEntitlement` (`pro`) is a key, but it's the entitlement id. To change default keys, edit the `defaultValue`s of `_androidKey`/`_iosKey`. There's no debug bypass: without real keys and an active `pro` entitlement, Pro tiles always open `ProScreen`.

## Platform config

- Android: `compileSdk = 37` is hard-coded because `permission_handler_android` 14 compiles against 37. `android.suppressUnsupportedCompileSdk=android-37` goes with it. Release builds are signed with the **debug** key; release signing isn't set up.
- iOS: the minimum is 15.0, set in the pbxproj; ML Kit's SwiftPM package won't build below it. The Podfile's `13.0` applies only to pods. Every plugin except `doc_scanner_kit` (CocoaPods only) builds via SwiftPM.
- Under SwiftPM, permission_handler enables a permission only when its `NS…UsageDescription` key is in `ios/Runner/Info.plist`. The Podfile `PERMISSION_*` macros apply only if SwiftPM is off, so keep the two in sync.
- Build iOS from the repo root with `flutter run` or `flutter build ios`. Builds started from Xcode.app can't locate `Info.plist`, so every permission gets compiled out and the camera reports denied, unless you set `PERMISSION_HANDLER_INFO_PLIST`.
