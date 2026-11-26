import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'diacritics.dart';
import 'engine.dart';
import 'page_text.dart';

/// Directory where every produced file lands (app-private, survives
/// reinstall-free use; share_plus/open-file can read it directly).
Future<Directory> outputsDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/pdf_utils');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// Directory holding saved signatures (PNG), created on demand.
Future<Directory> signaturesDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/pdf_utils/signatures');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// Saved signature PNGs, newest first.
Future<List<File>> listSignatures() async {
  final dir = await signaturesDir();
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.png'))
      .toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
}

/// Files produced by the app, newest first. Empty files are left out: a
/// failed run can leave its output opened but never written. Each file is
/// stat'ed once; one that vanishes meanwhile is skipped.
Future<List<File>> listOutputs() async {
  final dir = await outputsDir();
  final entries = <(File, DateTime)>[];
  for (final f in dir.listSync().whereType<File>()) {
    final stat = f.statSync();
    if (stat.type == FileSystemEntityType.file && stat.size > 0) {
      entries.add((f, stat.modified));
    }
  }
  entries.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (f, _) in entries) f];
}

/// A unique output file named `<stem>_<timestamp>.<ext>` in the outputs dir;
/// see [outputStem].
Future<File> outputFile(String baseName, String ext) async {
  final dir = await outputsDir();
  return File('${dir.path}/${outputStem(baseName)}.$ext');
}

/// [safeFileStem] of [baseName] plus the current time, so runs on files of
/// the same name don't overwrite each other. Tools that write several files
/// (one per page) name them `<outputStem>_trangN…`.
String outputStem(String baseName) =>
    '${safeFileStem(baseName)}_'
    '${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';

/// Deletes [file] if it exists, ignoring errors: used to clear what a failed
/// run left behind, where the error worth showing is the run's own.
void deleteQuietly(File? file) {
  try {
    if (file != null && file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // Best effort.
  }
}

/// [baseName] as a file-name stem: Vietnamese letters folded rather than
/// dropped, source extensions removed ("Hợp đồng.pdf_nen" → "Hop_dong_nen"),
/// anything else outside `[A-Za-z0-9_-]` removed and spaces turned into `_`.
String safeFileStem(String baseName) {
  final safe = removeDiacritics(baseName)
      .replaceAll(
        RegExp(
          r'\.(pdf|docx?|xlsx?|pptx?|png|jpe?g|heic|webp|txt)(?=_|$)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[^\w\- ]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  return safe.isEmpty ? 'pdf' : safe;
}

String fileBaseName(String path) => path.split('/').last;

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// Pick PDF files; null when cancelled or none selected.
Future<List<File>?> pickPdfs({bool multiple = false}) async {
  List<String?> paths;
  if (multiple) {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    paths = result.map((p) => p.path).toList();
  } else {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    paths = [result?.path];
  }
  final files = paths
      .whereType<String>()
      .map((p) => File(p))
      .where((f) => f.existsSync())
      .toList();
  return files.isEmpty ? null : files;
}

/// Pick one PDF, or a .txt such as a saved OCR result; null when cancelled.
Future<File?> pickPdfOrText() async {
  final result = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'txt'],
  );
  final path = result?.path;
  if (path == null) return null;
  final file = File(path);
  return file.existsSync() ? file : null;
}

/// The text of each page of [file], in composed Vietnamese: a PDF's pages,
/// or a .txt (such as a saved OCR result) split at its page markers.
Future<List<String>> readDocumentPages(File file) async {
  final pages = file.path.toLowerCase().endsWith('.txt')
      ? splitPageMarkers(
          utf8.decode(await file.readAsBytes(), allowMalformed: true),
        )
      : await PdfEngine.instance.pageTexts(file);
  return [for (final p in pages) composeVietnamese(p)];
}

/// The whole text of [file] without running headers and footers; see
/// [joinPages].
Future<String> readDocumentText(File file) async =>
    joinPages(await readDocumentPages(file));

/// Pick images; null when cancelled.
Future<List<File>?> pickImages({bool multiple = true}) async {
  final picker = ImagePicker();
  if (multiple) {
    final xs = await picker.pickMultiImage(imageQuality: 95);
    if (xs.isEmpty) return null;
    return xs.map((x) => File(x.path)).toList();
  }
  final x = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 95,
  );
  if (x == null) return null;
  return [File(x.path)];
}

/// Capture one photo with the camera; null when cancelled.
Future<File?> capturePhoto() async {
  final x = await ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 95,
  );
  if (x == null) return null;
  return File(x.path);
}

/// Reads bytes of an Android `content://` URI through a platform channel;
/// returns a temp file. On other platforms or on failure returns null.
Future<File?> contentUriToFile(String uri) async {
  if (!Platform.isAndroid) return null;
  const channel = MethodChannel('pdf_utils/content');
  try {
    final path = await channel.invokeMethod<String>('readContentUri', {
      'uri': uri,
    });
    if (path == null) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  } catch (_) {
    return null;
  }
}
