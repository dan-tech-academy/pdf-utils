import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// True redaction: render a page, drag rectangles over the content to hide,
/// the engine removes what is underneath permanently (not just covered).
class RedactScreen extends StatefulWidget {
  const RedactScreen({super.key});

  @override
  State<RedactScreen> createState() => _RedactScreenState();
}

class _RedactScreenState extends State<RedactScreen> {
  File? _input;
  List<PdfPageInfo> _pages = const [];
  int _page = 0;
  Uint8List? _pagePng;
  int _pngW = 0;
  int _pngH = 0;
  double _pageW = 0; // points
  double _pageH = 0;
  final List<Rect> _rects = []; // widget-space rects
  Offset? _dragStart;
  Rect? _dragRect;
  bool _running = false;
  File? _output;
  String? _error;
  PdfRedactionReport? _report;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    final f = files.first;
    setState(() {
      _input = f;
      _output = null;
      _error = null;
      _report = null;
    });
    try {
      _pages = await PdfEngine.instance.pageInfo(f);
      await _loadPage(0);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _loadPage(int page) async {
    final input = _input;
    if (input == null) return;
    final info = _pages[page];
    final bmp = await PdfEngine.instance.pageBitmap(input, page, dpi: 72);
    setState(() {
      _page = page;
      _pagePng = bmp.bytes;
      _pngW = bmp.width;
      _pngH = bmp.height;
      _pageW = info.mediaBox.width;
      _pageH = info.mediaBox.height;
      _rects.clear();
      _dragRect = null;
      _dragStart = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null || _rects.isEmpty) return;
    // Widget px → PDF points (y flips: widget y grows down, PDF y grows up).
    final regions = _rects.map((r) {
      final sx = _pageW / _pngW;
      final sy = _pageH / _pngH;
      final left = r.left * sx;
      final right = r.right * sx;
      final top = _pageH - r.top * sy;
      final bottom = _pageH - r.bottom * sy;
      return PdfRect.fromEdges(
        left: left,
        bottom: bottom,
        right: right,
        top: top,
      );
    }).toList();
    setState(() {
      _running = true;
      _error = null;
      _output = null;
      _report = null;
    });
    try {
      final out = await outputFile(
        '${fileBaseName(input.path)}_che',
        'pdf',
      );
      final report = await PdfEngine.instance.redact(
        input,
        out,
        _page,
        regions,
      );
      setState(() {
        _output = out;
        _report = report;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Che nội dung'),
        actions: [
          if (_rects.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.layers_clear),
              tooltip: 'Xóa vùng đã chọn',
              onPressed: () => setState(() => _rects.clear()),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf,
            label: 'Chọn PDF',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
            trailing: _pages.isNotEmpty
                ? Chip(label: Text('${_pages.length} trang'))
                : null,
          ),
          if (_pages.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DropdownButtonFormField<int>(
                initialValue: _page,
                decoration: const InputDecoration(
                  labelText: 'Trang cần che',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var i = 0; i < _pages.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('Trang ${i + 1}'),
                    ),
                ],
                onChanged: (v) => _loadPage(v!),
              ),
            ),
          if (_pagePng != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Kéo trên ảnh để chọn vùng cần che (vùng đỏ).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Center(
              child: ClipRect(
                child: SizedBox(
                  width: _pngW.toDouble(),
                  height: _pngH.toDouble(),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: GestureDetector(
                      onPanStart: (d) => setState(() {
                        _dragStart = d.localPosition;
                        _dragRect = null;
                      }),
                      onPanUpdate: (d) => setState(() {
                        _dragRect = Rect.fromPoints(
                          _dragStart!,
                          d.localPosition,
                        );
                      }),
                      onPanEnd: (_) => setState(() {
                        if (_dragRect != null &&
                            _dragRect!.width > 4 &&
                            _dragRect!.height > 4) {
                          _rects.add(_dragRect!);
                        }
                        _dragRect = null;
                        _dragStart = null;
                      }),
                      child: Stack(
                        children: [
                          Image.memory(_pagePng!, gaplessPlayback: true),
                          for (final r in _rects)
                            Positioned.fromRect(
                              rect: r,
                              child: Container(
                                color: Colors.red.withValues(alpha: 0.45),
                              ),
                            ),
                          if (_dragRect != null)
                            Positioned.fromRect(
                              rect: _dragRect!,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.25),
                                  border: Border.all(color: Colors.red),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('${_rects.length} vùng sẽ bị che.'),
            const SizedBox(height: 8),
            RunButton(
              label: 'Che vĩnh viễn & xuất PDF',
              onPressed: _run,
              enabled: !_running && _rects.isNotEmpty,
            ),
          ],
          const SizedBox(height: 16),
          if (_running) const RunningPane(message: 'Đang che nội dung…'),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null)
            ResultCard(
              file: _output!,
              extra: _report == null
                  ? null
                  : 'Đã che ${_report!.regionCount} vùng '
                      '(${_report!.glyphsRemoved} ký tự, '
                      '${_report!.imagesRemoved} ảnh gỡ bỏ)',
            ),
        ],
      ),
    );
  }
}
