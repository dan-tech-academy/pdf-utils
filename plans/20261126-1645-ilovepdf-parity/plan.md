# iLovePDF parity for office workers

Status: phases 1–2 done, phase 3 in review (2026-11-26). The tree analyzes clean and 48 tests pass.

## Goal (user)
A mobile app for Vietnamese office workers who work with PDFs. Everything free. A simple interface that is truly easy to use.
The user asked to check https://www.ilovepdf.com/ (35 tools) and build every tool the app lacks.

## Gap vs iLovePDF
- Already covered: merge, split, compress, organize, scan, JPG→PDF, Word/PPT/Excel ↔ PDF, PDF→JPG (PNG only), page numbers, watermark, crop, forms (fill), unlock/protect, sign, redact.
- To build: remove pages, extract pages, rotate, repair, PDF→PDF/A, HTML→PDF, edit PDF (text, freehand, boxes, highlight), compare, summarize, translate, OCR for scanned PDFs, PDF→Markdown (option in text extraction), PDF→JPG + extract embedded images.
- Built: all of the above (10 new home tools, 21 → 31, plus options inside existing tools). Compare and Summarize also accept `.txt`, so an OCR result can be fed in. Home has 6 groups and an accent-insensitive search.
- Not feasible: a searchable OCR PDF, because engine fonts cannot write Vietnamese and watermark text is not extractable (both verified with a probe), so OCR returns text instead. Also adding new form fields to an existing PDF, because the engine has no API for it.

## Bugs found (fixed in scope)
- Watermark text with Vietnamese renders as garbage (engine font). Text now renders with Flutter and is stamped as an image. Page-number patterns with diacritics go the same way.
- `outputFile()` dropped Vietnamese letters ("Hợp đồng" → "Hp_ng"). It now folds diacritics.
- Raw exception text was shown to users. Screens now show `friendlyError()`.

## Review round (2 independent reviewers)
- Fixed in shared code:
  - The crop box is now clipped to the media box in `PageGeometry`.
  - `PdfEngine` closes every output sink and `FileSource`. This leak predates this work.
  - PDF/A strips owner-only encryption, and `.jp2` is named correctly.
  - Decomposed Vietnamese is composed.
  - Running headers/footers are dropped (`page_text.dart`).
  - Home search matches word prefixes and ranks title matches first.
- Fixed in screens:
  - Scanned PDFs are OCR'd in place in compare/summarize/translate (`pdf_ocr.dart`). The old "save the .txt and pick it" advice was a dead end, because outputs are private.
  - Translate keeps partial results.
  - Options are locked during runs.
  - Multi-file outputs get timestamps.
  - PDF→Ảnh renders per page with a pixel cap.
  - Edit stamps only the marks' bounds.
  - Web→PDF can be cancelled and handles redirect/TLS/octet-stream cases.
- Accepted: overlays stay stamp annotations, since flattening would also flatten links and forms. This is documented in AGENTS.md.

## Phases
1. Foundations (done): engine wrappers, `page_overlay.dart`, `diacritics.dart`, `errors.dart`, deps (`printing`, `google_mlkit_translation`), INTERNET permission, tests.
2. [Screens](phase-02-screens.md), built by parallel subagents that only create or own their own files.
3. Integration: watermark/numbering fix, home groups + search, README/AGENTS, full verification.

## Acceptance
- `flutter analyze --no-pub` reports 0 issues. `flutter test --no-pub` passes. `flutter build apk --debug --no-pub` builds.
- Every iLovePDF tool either exists or is listed above as not feasible, with the reason.
- Vietnamese text renders correctly in watermark, numbering and edit outputs (checked on a rendered page).
