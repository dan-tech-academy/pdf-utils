# Phase 02: new tool screens

Each subagent owns only the files listed in its section. Read `AGENTS.md`, `lib/screens/compress_screen.dart` (the reference screen), `lib/widgets.dart`, `lib/files.dart`, `lib/engine.dart` and `lib/page_overlay.dart` first.

## Who the app is for
Vietnamese office workers on a phone, often not technical. Everything is free and runs on the device. "Truly easy to use" is the bar.

## UX rules (every screen)
- One StatefulWidget per tool in `lib/screens/`. Layout follows `compress_screen.dart`: a `ListView(padding: EdgeInsets.all(16))` with `PickTile` → options → `RunButton` (or `RunningPane` while running) → `ErrorBanner` → `ResultCard` / `ResultFilesCard`.
- All UI text is Vietnamese, in the words an office worker would use. No jargon (DPI, AcroForm, raster, OCR engine, XObject…). If a term can't be avoided, explain it once in brackets. Keep labels short and let long text wrap.
- Defaults must work: a user can pick a file and press the button without touching any option. Show at most about 3 options. Prefer `SegmentedButton` or `RadioGroup` + `RadioListTile` (see `compress_screen.dart`) over sliders when there are 2–4 choices.
- The `RunButton` label says the outcome: "Xóa 3 trang", "Xoay 2 file", "Tạo PDF".
- Add a one-line helper text (bodySmall, `colorScheme.onSurfaceVariant`) under the AppBar content when the tool needs a hint.
- Errors: `catch (e) { setState(() => _error = friendlyError(e)); }` with `import '../errors.dart';`. Write validation messages in Vietnamese.
- Outputs: `outputFile('${fileBaseName(input.path)}_<suffix>', '<ext>')`. The suffix is unaccented (`_xoay`, `_trich`…). Multi-file results go straight into `await outputsDir()`, because home lists only that folder.
- Take colours from `Theme.of(context).colorScheme`. Hard-code a colour only when it is content (pen/ink colours, highlight yellow).
- Check `mounted` after every await before calling `setState`. Run heavy pure-Dart work (diff, summary, image encoding) in `Isolate.run`.
- No fixed heights around text: layouts must survive large text scaling.
- Analyze reports deprecated APIs as infos, which fail it. Copy call patterns from existing files.

## Engine and helpers you can use
- `PdfEngine.instance` (`lib/engine.dart`): `pageInfo(file)` returns `List<PdfPageInfo>` (`mediaBox`, `cropBox`, `rotation`). Other methods: `rotatePages(in, out, by: PdfRotation.r90|r180|r270, pages: PdfPages.all())`, `removePages(in, out, [0-based])`, `keepPages(in, out, [0-based])`, `repair(in, out)`, `convertToPdfA(in, out)` (returns `PdfValidationReport` with `isCompliant`, `errorCount`), `addImageStamps(in, out, [ImageStamp])` (an `ImageStamp` is a record `(png:, bounds:, pages:, opacity:)`), `pageBitmap(file, page, dpi:)` (returns `PdfBitmap` with PNG `bytes`, `width` and `height`, already turned by `/Rotate`), `extractText(file, format: PdfExtractionFormat.plain|markdown)`, `pageTexts(file)` (one string per page), `extractImages(in, dir, base)` (JPEGs stay .jpg, others become .png; images under 8 px are skipped).
- `lib/page_overlay.dart`:
  - `PageGeometry(pdfPageInfo)` gives `width`/`height` in display points (the page as a reader sees it, y down), `toPdf(Rect displayRect)` → `PdfRect`, and `uprightForPage(png)`, which pre-turns an overlay PNG so it reads upright on pages with `/Rotate`.
  - `renderTextImage(text, fontSize:, color:, angleDegrees:)` returns `OverlayImage(png, width, height)` in points.
- `lib/files.dart`: `pickPdfs(multiple:)`, `pickImages()`, `outputFile`, `outputsDir`, `fileBaseName`, `formatBytes`.
- `lib/widgets.dart`: `PickTile`, `PickedFilesList`, `RunButton`, `RunningPane`, `ResultCard(file:, extra:)`, `ResultFilesCard(files:)`, `ErrorBanner(message:)`, `IconTile`.

## Engine limits (verified, don't fight them)
- Text the engine writes into a PDF can't show Vietnamese, and watermark text isn't extractable. Anything that writes text onto a page must draw it with Flutter (`renderTextImage`, or a `PictureRecorder` overlay) and stamp the result as an image.
- Rendering outputs PNG or raw RGBA only. For JPG, encode with `package:image` (already a dependency) inside `Isolate.run`.

## Rules for subagents
- Only create or edit the files in your section. Don't touch `lib/engine.dart`, `lib/files.dart`, `lib/widgets.dart`, `lib/home_screen.dart`, `lib/errors.dart`, `lib/page_overlay.dart`, `lib/diacritics.dart`, `pubspec.yaml`, `README.md`, `AGENTS.md` or existing tests. If you need a change there, describe it in your report.
- Don't run `flutter pub get`, any build, or `dart format` on files you don't own. Format your own new files with `dart format <files>`.
- Verify with `dart analyze --fatal-infos <your files>`: no issues allowed. Other agents edit in parallel, so don't analyze the whole project. Pure-Dart logic gets unit tests in `test/<name>_test.dart`, run with `flutter test --no-pub test/<name>_test.dart`.
- Don't commit. Don't register tools on home: the controller does that with the class names below.
- End your report with `Status: DONE | DONE_WITH_CONCERNS | BLOCKED`, a list of the files you touched, and the exact Vietnamese AppBar title of each screen.

## A. Page tools
Files: `lib/screens/select_pages_screen.dart`, `lib/screens/rotate_screen.dart`.
- `SelectPagesScreen({required SelectPagesMode mode})`, with `enum SelectPagesMode { remove, extract }`.
  - Titles: "Xóa trang" and "Trích trang".
  - Flow: pick a PDF, then show a grid of page thumbnails (copy the thumbnail rendering and the 200-page cap from `pages_screen.dart`). Each thumbnail shows its page number. Tapping toggles a selection with a clear checkmark.
  - Hints: "Chạm vào trang muốn xóa" / "Chạm vào trang muốn lấy ra thành file mới".
  - Provide "Chọn tất cả" / "Bỏ chọn".
  - Button: "Xóa N trang" / "Lấy N trang". Refuse to remove every page, with a Vietnamese message.
  - Engine calls: `removePages` / `keepPages`. Suffixes: `_xoatrang` / `_trichtrang`.
- `RotateScreen`, titled "Xoay PDF".
  - Pick one or more PDFs (`pickPdfs(multiple: true)`) and list them with `PickedFilesList`.
  - Direction: a `SegmentedButton` with "Xoay phải" (r90, the default), "Xoay trái" (r270) and "Lật ngược" (r180). Show a small preview of the first file's first page turned with `RotatedBox`.
  - Rotate every page of every file; suffix `_xoay`. Button: "Xoay N file". One output → `ResultCard`, several → `ResultFilesCard`.

## B. Repair, PDF/A, web page, images, Markdown
Files: `lib/screens/repair_screen.dart`, `lib/screens/pdfa_screen.dart`, `lib/screens/web_to_pdf_screen.dart`, `lib/screens/pdf_to_images_screen.dart` (edit), `lib/screens/text_screen.dart` (edit).
- `RepairScreen`, titled "Sửa PDF lỗi".
  - Hint: "Dùng khi file PDF không mở được hoặc báo lỗi."
  - Runs `repair`; suffix `_dasua`. The result's extra line shows the page count read from the output.
  - If repair fails, say plainly that the file is too damaged to recover.
- `PdfaScreen`, titled "PDF/A (lưu trữ)".
  - Hint: "Chuẩn lưu trữ lâu dài, thường được yêu cầu khi nộp hồ sơ điện tử."
  - Runs `convertToPdfA`; suffix `_pdfa`. Extra line: "Đạt chuẩn PDF/A-2b" or "Đã chuyển, còn N điểm chưa đạt chuẩn".
- `WebToPdfScreen`, titled "Trang web → PDF".
  - A URL field (url keyboard, hint "vd: vnexpress.net/bai-viet…"). Add `https://` when there's no scheme.
  - Fetch the HTML with `dart:io` `HttpClient`: 20 s timeout, follow redirects, decode with the response charset and fall back to UTF-8 with `allowMalformed`. Then call `Printing.convertHtml(html: html, baseUrl: finalUrl)` from `package:printing/printing.dart` (it defaults to A4; don't import `package:pdf`).
  - Name the output after the host; suffix `_web`.
  - Hint: "Hợp với bài báo, trang tin. Trang phải đăng nhập sẽ không tải được."
- `pdf_to_images_screen.dart` (existing):
  - Add a mode `SegmentedButton`: "Mỗi trang một ảnh" (render, the default) / "Lấy ảnh trong file" (`extractImages` into `outputsDir()`).
  - Render mode gets a format choice: "JPG (nhẹ)" (the default) / "PNG (nét nhất)". As built after review: render page by page with `pageBitmap`, capping the long side at about 6000 px, encode JPG at quality ~85 in `Isolate.run`, and name files `outputStem(...)_trangN` so reruns don't overwrite.
  - Replace DPI wording with plain words: "Thường / Nét / Rất nét".
- `text_screen.dart` (existing): add an output choice "Văn bản (.txt)" (default) / "Markdown (.md)" using `extractText(format:)`.

## C. Edit PDF
File: `lib/screens/edit_screen.dart`.
- `EditScreen`, titled "Chỉnh sửa PDF". Hint: "Thêm chữ, vẽ, đóng khung hoặc tô sáng lên trang."
- Pick a PDF, then show one page at a time: the `pageBitmap` (~110 dpi) inside a `LayoutBuilder`, with page navigation "‹ Trang 2/10 ›". The canvas must not sit inside a scrolling view.
- Tools (a `SegmentedButton`):
  - Chữ: tap the page, a dialog asks for text and size (Nhỏ/Vừa/Lớn), and the text is placed at the tap point.
  - Vẽ: freehand pen.
  - Khung: drag a rectangle outline.
  - Tô sáng: drag a semi-transparent yellow rectangle.
- Colours: Đen, Đỏ, Xanh (content colours, hard-coded is fine).
- Also "Hoàn tác" (undo) and "Xóa hết trang này". Keep edits per page so several pages can be edited before saving.
- Save ("Lưu PDF"): for each edited page, build `PageGeometry` from `pageInfo` and draw that page's edits in display points into a `PictureRecorder` at ~3 px/pt. Draw text with `TextPainter` in fontFamily `BeVietnamPro`.
- As built after review, the drawing covers only the bounding box of the page's marks (`marksArea`), not the whole page, so the stamp doesn't block links, form fields or text selection. Turn the result with `uprightForPage` and stamp it at `toPdf(area)` through one `addImageStamps` call. Suffix `_dasua_noidung`.
- Map gesture positions to display points with `point / (widgetWidth / g.width)`.

## D. Compare and summarize
Files: `lib/text_diff.dart`, `lib/summarizer.dart`, `lib/screens/compare_screen.dart`, `lib/screens/summarize_screen.dart`, `test/text_diff_test.dart`, `test/summarizer_test.dart`.
- `text_diff.dart`: a word-level diff, `List<DiffChunk> diffWords(String oldText, String newText)` where `DiffChunk` has a type (equal/insert/delete) and text.
  - It must stay fast on ~50k words: Myers, or a line-level pass first with a word-level pass inside changed blocks.
  - Normalize whitespace so line-wrapping differences don't count as changes.
- `CompareScreen`, titled "So sánh PDF".
  - Two `PickTile`s, "Bản cũ" and "Bản mới". Button: "So sánh".
  - Text comes from `extractText`; diff in `Isolate.run`.
  - Summary: "Thêm X chỗ · Xóa Y chỗ". Show only the changed regions, with ~8 words of context each: additions on `primaryContainer`, deletions struck through on `errorContainer`.
  - If nothing changed: "Hai file giống nhau về nội dung chữ."
  - If either file has no text: suggest running "Nhận dạng chữ (OCR)" first.
  - Note: "Chỉ so sánh phần chữ, không so sánh hình ảnh."
- `summarizer.dart`: extractive summary, `List<String> summarize(String text, {int maxSentences = 7})`.
  - Split sentences on Vietnamese/English punctuation and newlines; drop fragments shorter than about 5 words.
  - Rank with TextRank: similarity = shared lowercased words / (log|a| + log|b|), damping 0.85, ~30 iterations. Cap at ~500 sentences.
  - Return the chosen sentences in original order. Deterministic.
- `SummarizeScreen`, titled "Tóm tắt PDF".
  - Length: "Ngắn" (5) / "Vừa" (10, the default) / "Chi tiết" (20). Button: "Tóm tắt".
  - Show the sentences as a bullet list, with actions "Sao chép", "Chia sẻ" and "Lưu .txt" (suffix `_tomtat`, shown with `ResultCard`).
  - Honest hint: "Chọn ra những câu quan trọng nhất trong file, chạy ngay trên máy."
  - A file without text gets the OCR suggestion.

## E. Translate and OCR for scanned PDFs
Files: `lib/screens/translate_screen.dart`, `lib/screens/ocr_screen.dart` (edit).
- `TranslateScreen`, titled "Dịch PDF".
  - Pick a PDF. "Từ" defaults to Tiếng Anh, "Sang" to Tiếng Việt; offer Tiếng Việt, Anh, Trung, Nhật, Hàn and a swap button.
  - Use `google_mlkit_translation` 1.0.3. Read its source in `~/.pub-cache/hosted/pub.dev/google_mlkit_translation-1.0.3/` for the exact API: `OnDeviceTranslator`, `TranslateLanguage` and `OnDeviceTranslatorModelManager`.
  - If a model is missing, download it first, with the message "Đang tải gói ngôn ngữ (chỉ lần đầu, cần Internet)…".
  - Translate page by page with `pageTexts`, paragraph by paragraph, showing progress "Đang dịch trang 3/10" and offering Hủy.
  - Show the result text with "Sao chép", "Chia sẻ" and "Lưu .txt" (suffix `_dich`). Close the translator in `dispose`.
  - Hint: "Bản dịch giữ nội dung, không giữ bố cục trang. Chạy ngay trên máy."
- `ocr_screen.dart` (existing): add a second source, "Chọn PDF bản scan".
  - Render each page with `pageBitmap` at ~200 dpi to a temporary PNG, run the same ML Kit recognizer, and join the pages with "--- Trang N ---".
  - Show progress "Đang nhận dạng trang 2/8" with Hủy.
  - Set the AppBar title to "Nhận dạng chữ (OCR)". Keep the existing image flow and its copy/save actions.
