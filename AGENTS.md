# AGENTS.md

Single-package Flutter app (Android + iOS) with no CI. It has 31 on-device PDF tools, all free, with no in-app purchases or ads. PDF ops run on the Rust engine in `pdf_manipulator`.
It's built for Vietnamese office workers, so the UI must stay truly easy: plain Vietnamese words (no jargon like DPI or AcroForm), defaults that work without touching options, and few choices per screen.
User-facing text (UI, README, `Info.plist` usage strings) is hard-coded in Vietnamese, with no l10n. Code, identifiers and comments are in English.

## Verify

- Run `flutter pub get` once, then `flutter analyze --no-pub` → `flutter test --no-pub`. Local runs are the only gate. `--no-pub` matters: see the xcconfig note below.
- `flutter analyze` exits 1 even on infos. The tree is clean (0 issues), so any info is yours.
- Don't run `dart format` over existing files. Most aren't format-clean, so it buries real diffs. Format only new files.
- `test/widget_test.dart` is a home smoke test that checks several Vietnamese tool titles exactly, plus the accent-insensitive search. Home builds every row eagerly (a Column in a scroll view), which is why titles below the fold are found. A lazy `ListView`/builder breaks the test.
- `test/engine_test.dart` covers the engine wrappers the newer tools use, and pins how an overlay is stamped on a rotated page. The pure-Dart helpers have their own tests (`text_helpers`, `text_diff`, `summarizer`, `translation_chunks`).
- `test/edit_overlay_test.dart` drives a real screen with a picked file. Set `FilePickerPlatform.instance` to a fake; the fake file must be a `final class`, because `PlatformFile` is an `abstract base class`. Then alternate `tester.runAsync(() => Future.delayed(...))` with `pump()` so the real engine work finishes. Copy that pattern to test other screens.
- `flutter test` doesn't load the bundled fonts. Text renders in Flutter's placeholder test font, about 1.7× wider than Be Vietnam Pro, so overflow checks and goldens mean nothing until a test loads `assets/fonts/*.ttf` with `FontLoader`.
- Engine ops run natively under plain `flutter test`, because the hook supplies a host binary. So test `PdfEngine` with `test()` and files in `Directory.systemTemp`. Don't use `outputFile()`/`outputsDir()` in tests: path_provider throws `MissingPluginException` there. Pickers, ML Kit (OCR, translation) and `printing` don't work in tests either.

## Toolchain gotchas

- Needs Flutter ≥3.47 / Dart ≥3.13.5. The deps are newer than most docs and examples (file_picker 13, share_plus 13, Material `RadioGroup`), so copy call patterns from `lib/files.dart`, `lib/widgets.dart`, `lib/theme.dart` and `screens/compress_screen.dart`. Deprecated APIs show up as infos, which fail analyze. Theme data, for example, must use `AppBarThemeData`, `CardThemeData` and `InputDecorationThemeData`.
- `pdf_manipulator` is pinned to exactly `6.0.0`; keep it exact. Its native-assets hook downloads a prebuilt engine of about 25 MB into `.dart_tool/hooks_runner/`. That happens on the first build **and** the first `flutter test`, so both need network. Offline, or when you trim the engine through pubspec `hooks.user_defines` (`keep`, `build: size`), the hook compiles vendored Rust instead, which needs rustup.
- Any command that runs pub get (including analyze/test/run/build without `--no-pub`) adds a CocoaPods `#include?` line to the tracked `ios/Flutter/{Debug,Release}.xcconfig`. Keep that change out of unrelated commits by reverting it with `git checkout -- 'ios/Flutter/*.xcconfig'`. The quotes matter: unquoted, the glob also matches the untracked `Generated.xcconfig`, git fails and nothing gets reverted.

## Architecture

- `main.dart` → `HomeScreen` (`home_screen.dart`; its `_groups` list defines the sectioned home list) → one StatefulWidget per tool in `lib/screens/`. State is plain `setState` plus the `PdfEngine.instance` singleton. There's no router or state-management package.
- Styling lives in `lib/theme.dart`: an explicit navy/silver `ColorScheme`, the text theme and component themes. Light and dark follow the system. Screens take colours from `Theme.of(context).colorScheme`. The only hard-coded colours are functional: the signature pad's white paper and black ink, and the red redaction overlay. Component themes rarely need a `textStyle`, because Material defaults read the text theme. A `ButtonStyle.textStyle` replaces the ambient style, though, so one set without `fontFamily` silently drops back to the platform font.
- Be Vietnam Pro is bundled in `assets/fonts` (OFL) with weights 400/500/600 only; heavier requests render as 600. It has no `→`/`↔` glyphs, which appear in several tool titles. Devices draw them from a system fallback font.
- Text written onto pages (watermark, page numbers, the edit tool) is drawn by Flutter in Be Vietnam Pro (`renderTextImage` or a `PictureRecorder` overlay) and stamped with `PdfEngine.addImageStamps`. The engine's own text (watermarks, `PdfBuilder` text) uses PDF base fonts that turn Vietnamese into garbage, and its watermark text isn't extractable. That is also why there is no searchable OCR PDF.
- `PageGeometry` (`lib/page_overlay.dart`) maps display points (the page as a reader sees it, which is what `pageBitmap` renders) to PDF space. It also pre-turns overlays for `/Rotate`. `redact_screen.dart` predates it and assumes unrotated pages.
- Show errors with `friendlyError(e)` (`lib/errors.dart`), never raw `e.toString()`. Copy text with `copyText(context, text)` (`lib/widgets.dart`): Android rejects clipboard data over about 1 MB.
- Write files through `PdfEngine` methods, which close every output sink and `FileSource` they open (`_writeTo`). The library never closes what it is handed, though it does close the per-part sinks it asks for in split, render and `extractImages`. Name multi-file outputs with `outputStem()` so reruns don't overwrite. Clear a failed run's output with `deleteQuietly()`; home also hides 0-byte files.
- Tools that read a document's text (compare, summarize, translate) use `readDocumentPages`/`readDocumentText` (`lib/files.dart`). These accept a PDF or an app-saved .txt, compose decomposed Vietnamese (`composeVietnamese`), and drop running headers/footers (`joinPages` in `lib/page_text.dart`). Saved text separates pages with `pageMarker(n)`. A scanned PDF with no text is OCR'd in place through `lib/pdf_ocr.dart`. Don't tell users to pick a saved .txt: outputs live in the app's private folder, which system pickers can't see.
- Overlays (watermark, page numbers, edits) are stamp annotations flagged print + locked. Viewers show and print them, but annotation editors can remove them. `flattenAnnotations` would bake them in, but it also flattens the page's links and form fields, so it isn't used.
- Every PDF op goes through `PdfEngine` (`lib/engine.dart`). pdf_manipulator doesn't export `PdfDocument`/`PdfEditor`, so those types can't be named in fields, parameters or helpers. Keep `read`/`rewrite` callbacks inline in `PdfEngine` methods. Don't import `package:pdf_manipulator/src/...`, because it trips `implementation_imports`. `FileSource`, `FileSink` and `PdfFile` come from `package:pdf_manipulator/io.dart`, not the main barrel.
- Screen flow: `pickPdfs()`/`pickImages()` → `outputFile(base, ext)` (or `outputsDir()` for multi-file ops) → engine op → `RunningPane`/`ResultCard`/`ErrorBanner` from `lib/widgets.dart`. The home "File đã tạo" list shows only files directly in `<Documents>/pdf_utils/`. `outputFile()` folds Vietnamese letters (`safeFileStem`: "Hợp đồng.pdf" → "Hop_dong") and drops other non-ASCII; keep filename suffixes unaccented (`_nen`, `_cat`).
- Engine page indices are 0-based; the UI shows 1-based. `PdfRect` is in PDF points with y pointing up. Convert from widget/bitmap pixels with `PageGeometry.toPdf` (scale pixels to display points first), not the hand-rolled maths in `redact_screen.dart` `_run()`.
- The Android-only MethodChannel `pdf_utils/content` (`readContentUri` in `MainActivity.kt`) backs `contentUriToFile()` for the scanner's `content://` results. On iOS, `contentUriToFile()` returns null.

## Adding or renaming a tool

1. Build the screen in `lib/screens/` with the flow above, then add it to the right group in `_groups` in `home_screen.dart`. Order there is display order. Give it `keywords:` (unaccented synonyms and English names) so the home search finds it.
2. Update the README counts, table and tree. Update `test/widget_test.dart` if a checked title changed.

## Platform config

- Network is used only by Trang web → PDF (`printing`'s `convertHtml`) and by ML Kit translation, which downloads each language model on first use. Android declares `INTERNET` in the main manifest for release builds.
- `Printing.convertHtml` is deprecated without a replacement, so its one call carries an `ignore: deprecated_member_use`. It is still maintained natively (5.15.1 fixed iOS 26). Its Android web view runs without JavaScript, so images a page loads by script are missing. If a printing major drops it, Web → PDF needs its own native WebView-print code.
- Android: `compileSdk = 37` is hard-coded because `permission_handler_android` 14 compiles against 37. `android.suppressUnsupportedCompileSdk=android-37` goes with it. Release builds are signed with the **debug** key; release signing isn't set up.
- iOS: the minimum is 15.0, set in the pbxproj; ML Kit's SwiftPM package won't build below it. The Podfile's `13.0` applies only to pods. Every plugin except `doc_scanner_kit` (CocoaPods only) builds via SwiftPM.
- Under SwiftPM, permission_handler enables a permission only when its `NS…UsageDescription` key is in `ios/Runner/Info.plist`. The Podfile `PERMISSION_*` macros apply only if SwiftPM is off, so keep the two in sync.
- Build iOS from the repo root with `flutter run` or `flutter build ios`. Builds started from Xcode.app can't locate `Info.plist`, so every permission gets compiled out and the camera reports denied, unless you set `PERMISSION_HANDLER_INFO_PLIST`.
