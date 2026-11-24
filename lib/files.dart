import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

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

/// Files produced by the app, newest first.
Future<List<File>> listOutputs() async {
  final dir = await outputsDir();
  final files = dir
      .listSync()
      .whereType<File>()
      .toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  return files;
}

/// A unique output file named `<base>_<timestamp>.<ext>` in the outputs dir.
Future<File> outputFile(String baseName, String ext) async {
  final dir = await outputsDir();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final safe = baseName
      .replaceAll(RegExp(r'\.pdf$'), '')
      .replaceAll(RegExp(r'[^\w\- ]'), '')
      .trim()
      .replaceAll(' ', '_');
  final name = '${safe.isEmpty ? 'pdf' : safe}_$stamp.$ext';
  return File('${dir.path}/$name');
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
    final path = await channel.invokeMethod<String>(
      'readContentUri',
      {'uri': uri},
    );
    if (path == null) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  } catch (_) {
    return null;
  }
}
