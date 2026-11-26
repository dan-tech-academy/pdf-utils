/// On-device text recognition (OCR) with ML Kit's Latin model, which reads
/// Vietnamese. The OCR tool uses it for photos and scanned PDFs. The tools
/// that read a document's text (compare, summarize, translate) use it when
/// the PDF they get is a scan.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' show PdfPageInfo;

import 'diacritics.dart';
import 'engine.dart';
import 'files.dart';

/// Progress of a recognition run: [done] of [total] pages (or photos) are
/// finished and the next one is being read.
typedef OcrProgress = void Function(int done, int total);

/// A document's text, one string per page, and whether that text was
/// recognized on the page images because the file is a scan.
typedef DocumentPages = ({List<String> pages, bool scanned});

/// Shown with results built from recognized text.
const scannedTextNote =
    'Chữ được nhận dạng từ bản scan nên có thể có vài chỗ sai.';

/// Resolution pages are rendered at for recognition: enough for small print.
const _pageDpi = 200;

/// Longest side, in pixels, of a page rendered for recognition.
const _maxPagePixels = 3500;

/// The progress line while [subject] ("File", "Bản cũ"…) is read as a scan.
String scanProgressText(String subject, int done, int total) =>
    '$subject là bản scan, đang nhận dạng chữ'
    '${total > 1 ? ' trang ${done + 1}/$total' : ''}…';

/// The text of each page of [file] as [readDocumentPages] reads it. For a
/// scan, the pages [pagesToRecognize] picks get the text [recognizePdfPages]
/// finds on their images instead, reporting each page to [onScanProgress].
/// Null when [isCancelled] stopped the recognition before the last page.
Future<DocumentPages?> readOrRecognizePages(
  File file, {
  required OcrProgress onScanProgress,
  required bool Function() isCancelled,
}) async {
  final pages = await readDocumentPages(file);
  final blank = pagesToRecognize(file, pages);
  if (blank.isEmpty) return (pages: pages, scanned: false);
  if (isCancelled()) return null;
  final read = await recognizePdfPages(
    file,
    only: blank,
    onProgress: onScanProgress,
    isCancelled: isCancelled,
  );
  if (read.length < blank.length) return null;
  final merged = [...pages];
  for (var k = 0; k < blank.length; k++) {
    merged[blank[k]] = read[k];
  }
  return (pages: merged, scanned: true);
}

/// A page with fewer letters than this has no real text layer: scanner apps
/// often add one line such as "Scanned with CamScanner" or a page number.
const _minLetters = 40;

final _letter = RegExp(r'\p{L}', unicode: true);

/// The pages of [file] to read with OCR: none for a .txt or a PDF that
/// mostly has text; otherwise every page with almost no text, when such
/// pages are at least half the file. A normal document with a few picture
/// pages is not OCR'd.
@visibleForTesting
List<int> pagesToRecognize(File file, List<String> pages) {
  if (file.path.toLowerCase().endsWith('.txt') || pages.isEmpty) {
    return const [];
  }
  final blank = [
    for (var i = 0; i < pages.length; i++)
      if (_letter.allMatches(pages[i]).length < _minLetters) i,
  ];
  return blank.length * 2 >= pages.length ? blank : const [];
}

/// The text recognized on each page of [pdf] (or each page index in [only]),
/// one trimmed string per page in composed Vietnamese, empty for a page
/// without text.
///
/// [onProgress] is called before each page. [isCancelled] is checked before
/// each page too. Once it returns true, the pages read so far are returned,
/// fewer than asked for. A page already being read is finished first.
Future<List<String>> recognizePdfPages(
  File pdf, {
  List<int>? only,
  required OcrProgress onProgress,
  required bool Function() isCancelled,
}) async {
  final pages = await PdfEngine.instance.pageInfo(pdf);
  final indices = only ?? [for (var i = 0; i < pages.length; i++) i];
  final dir = await (await getTemporaryDirectory()).createTemp('ocr_');
  try {
    return await _recognizeEach(
      indices.length,
      (recognizer, k) =>
          _readPage(recognizer, pdf, indices[k], pages[indices[k]], dir),
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  } finally {
    await dir.delete(recursive: true).catchError((Object _) => dir);
  }
}

/// The text recognized in each of [images], as [recognizePdfPages] does for
/// pages.
Future<List<String>> recognizeImages(
  List<File> images, {
  required OcrProgress onProgress,
  required bool Function() isCancelled,
}) => _recognizeEach(
  images.length,
  (recognizer, i) async =>
      (await recognizer.processImage(InputImage.fromFile(images[i]))).text,
  onProgress: onProgress,
  isCancelled: isCancelled,
);

/// Reads items 0 to [total] - 1 with [read], sharing one recognizer that is
/// always closed afterwards. See [recognizePdfPages] for the callbacks.
Future<List<String>> _recognizeEach(
  int total,
  Future<String> Function(TextRecognizer recognizer, int index) read, {
  required OcrProgress onProgress,
  required bool Function() isCancelled,
}) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final texts = <String>[];
    for (var i = 0; i < total && !isCancelled(); i++) {
      onProgress(i, total);
      texts.add(composeVietnamese((await read(recognizer, i)).trim()));
    }
    return texts;
  } finally {
    await recognizer.close().catchError((Object _) {});
  }
}

/// Renders page [index] of [pdf] to a temporary PNG in [dir], reads its
/// text and deletes the PNG again.
Future<String> _readPage(
  TextRecognizer recognizer,
  File pdf,
  int index,
  PdfPageInfo info,
  Directory dir,
) async {
  final bitmap = await PdfEngine.instance.pageBitmap(
    pdf,
    index,
    dpi: _dpiFor(info),
  );
  final png = File('${dir.path}/trang_${index + 1}.png');
  try {
    await png.writeAsBytes(bitmap.bytes);
    final result = await recognizer.processImage(
      InputImage.fromFilePath(png.path),
    );
    return result.text;
  } finally {
    await png.delete().catchError((Object _) => png);
  }
}

/// [_pageDpi], but at most [_maxPagePixels] on the long side: some scanner
/// apps size each page like the photo in points, and 200 dpi on such a page
/// would run out of memory.
int _dpiFor(PdfPageInfo info) {
  final box = info.cropBox ?? info.mediaBox;
  final longest = math.max(box.width.abs(), box.height.abs());
  if (longest <= 0) return _pageDpi;
  return math.max(
    1,
    math.min(_pageDpi, (_maxPagePixels * 72 / longest).floor()),
  );
}
