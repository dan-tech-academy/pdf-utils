import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../page_overlay.dart';
import '../widgets.dart';

/// Whether each page becomes one picture, or the pictures already inside
/// the file are taken out.
enum _Mode { render, extract }

class PdfToImagesScreen extends StatefulWidget {
  const PdfToImagesScreen({super.key});

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  /// Longest side, in pixels, of a page image. A page sized like a poster,
  /// or like a photo as some scanner apps make them, would otherwise take
  /// hundreds of megabytes to render and encode.
  static const _maxPagePixels = 6000;

  File? _input;
  _Mode _mode = _Mode.render;
  bool _jpg = true;
  int _dpi = 150;
  bool _running = false;
  bool _cancelRequested = false;
  String _status = '';
  List<File>? _outputs;
  String? _notice;
  String? _error;

  /// Sharpness in plain words, as render resolutions (dots per inch).
  static const _sharpness = <(String, int)>[
    ('Thường', 100),
    ('Nét', 150),
    ('Rất nét', 300),
  ];

  /// True once the user pressed Hủy or left the screen.
  bool get _stopped => _cancelRequested || !mounted;

  Future<void> _pick() async {
    // A new file mid-run would end up shown with the old file's images.
    if (_running) return;
    final files = await pickPdfs();
    if (!mounted || _running || files == null || files.isEmpty) return;
    setState(() {
      _input = files.first;
      _outputs = null;
      _notice = null;
      _error = null;
    });
  }

  void _cancel() {
    setState(() {
      _cancelRequested = true;
      _status = 'Đang dừng…';
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null || _running) return;
    final mode = _mode;
    final jpg = _jpg;
    final dpi = _dpi;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _status = mode == _Mode.render ? 'Đang mở file…' : 'Đang lấy ảnh…';
      _error = null;
      _notice = null;
      _outputs = null;
    });
    Directory? dir;
    String? stem;
    try {
      dir = await outputsDir();
      stem = _runStem(dir, fileBaseName(input.path));
      if (mode == _Mode.extract) {
        final files = await PdfEngine.instance.extractImages(input, dir, stem);
        if (!mounted) return;
        setState(() {
          if (files.isEmpty) {
            _error = 'File này không có ảnh nào để lấy ra.';
          } else {
            _outputs = files;
          }
        });
        return;
      }
      // One page at a time, straight into the outputs folder, so a long
      // file never holds more than one page in memory.
      final pages = await PdfEngine.instance.pageInfo(input);
      final ext = jpg ? 'jpg' : 'png';
      final files = <File>[];
      // Hủy takes effect between pages: the page being saved is finished.
      for (var i = 0; i < pages.length && !_stopped; i++) {
        setState(() => _status = 'Đang lưu ảnh ${i + 1}/${pages.length}');
        final bitmap = await PdfEngine.instance
            .pageBitmap(input, i, dpi: _pageDpi(pages[i], dpi));
        final out = File('${dir.path}/${stem}_trang${i + 1}.$ext');
        if (jpg) {
          await _writeJpg(bitmap.bytes, out.path);
        } else {
          await out.writeAsBytes(bitmap.bytes);
        }
        files.add(out);
      }
      if (!mounted) return;
      setState(() {
        if (files.isNotEmpty) _outputs = files;
        if (pages.isEmpty) {
          _error = 'File này không có trang nào.';
        } else if (files.length < pages.length) {
          _notice = files.isEmpty
              ? 'Đã dừng, chưa lưu ảnh nào.'
              : 'Đã dừng sau trang ${files.length}/${pages.length}. '
                  'Các ảnh đã lưu vẫn được giữ lại.';
        }
      });
    } catch (e) {
      // A failed run keeps none of its images, finished or not.
      if (dir != null && stem != null) _discardRun(dir, stem);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// [dpi], lowered for a very large page so the long side of its image
  /// stays within [_maxPagePixels] (pixels = points × dpi / 72).
  static int _pageDpi(PdfPageInfo info, int dpi) {
    final g = PageGeometry(info);
    final longest = math.max(g.width, g.height);
    if (longest <= 0) return dpi;
    return math.max(1, math.min(dpi, (_maxPagePixels * 72 / longest).floor()));
  }

  /// [outputStem] of [source], with `_2`, `_3`… added while [dir] holds
  /// images under that name: its time only counts whole seconds. Each run
  /// thus owns every file named `<stem>_trang…`.
  static String _runStem(Directory dir, String source) {
    final names = [for (final e in dir.listSync()) fileBaseName(e.path)];
    final base = outputStem(source);
    var stem = base;
    for (var n = 2; names.any((s) => s.startsWith('${stem}_trang')); n++) {
      stem = '${base}_$n';
    }
    return stem;
  }

  /// Deletes every image a failed run wrote under [stem], finished or not.
  static void _discardRun(Directory dir, String stem) {
    try {
      for (final f in dir.listSync().whereType<File>()) {
        if (fileBaseName(f.path).startsWith('${stem}_trang')) {
          deleteQuietly(f);
        }
      }
    } on FileSystemException {
      // Best effort: the run's own error is the one to show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final render = _mode == _Mode.render;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF → Ảnh')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF',
            picked: _input?.path.split('/').last,
            onPick: _pick,
          ),
          const SizedBox(height: 16),
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(
                value: _Mode.render,
                label: Text('Mỗi trang một ảnh'),
              ),
              ButtonSegment(
                value: _Mode.extract,
                label: Text('Lấy ảnh trong file'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged:
                _running ? null : (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            render
                ? 'Mỗi trang PDF thành một tấm ảnh.'
                : 'Lấy ra các hình có sẵn trong file (ảnh chụp, logo…), '
                    'giữ nguyên chất lượng.',
            style: hint,
          ),
          if (render) ...[
            const SizedBox(height: 16),
            Text('Loại ảnh', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('JPG (nhẹ)')),
                ButtonSegment(value: false, label: Text('PNG (nét nhất)')),
              ],
              selected: {_jpg},
              onSelectionChanged:
                  _running ? null : (s) => setState(() => _jpg = s.first),
            ),
            const SizedBox(height: 16),
            Text('Độ nét', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (final (label, dpi) in _sharpness)
                  ButtonSegment(value: dpi, label: Text(label)),
              ],
              selected: {_dpi},
              onSelectionChanged:
                  _running ? null : (s) => setState(() => _dpi = s.first),
            ),
          ],
          const SizedBox(height: 16),
          if (_running)
            RunningPane(
              message: _status,
              // Pages are saved one by one, so that can stop in between;
              // taking out the pictures is a single step.
              onCancel: !render || _cancelRequested ? null : _cancel,
            )
          else
            RunButton(
              label: render
                  ? 'Xuất ảnh ${_jpg ? 'JPG' : 'PNG'}'
                  : 'Lấy ảnh ra',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_notice != null) ...[
            Text(_notice!, style: hint),
            const SizedBox(height: 8),
          ],
          if (_outputs != null) ResultFilesCard(files: _outputs!),
        ],
      ),
    );
  }
}

/// Encodes the rendered page [png] as a JPG at [path] in a background
/// isolate, so large pages don't freeze the screen.
Future<void> _writeJpg(Uint8List png, String path) =>
    Isolate.run(() => _pngToJpgFile(png, path));

/// JPG has no transparency, so see-through pixels land on white paper.
void _pngToJpgFile(Uint8List png, String path) {
  final page = img.decodePng(png);
  if (page == null) {
    throw FormatException('Rendered page is not a readable PNG', path);
  }
  page.backgroundColor = img.ColorRgb8(255, 255, 255);
  File(path).writeAsBytesSync(img.encodeJpg(page, quality: 85));
}
