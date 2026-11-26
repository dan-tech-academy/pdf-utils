import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// N-up: places 2/4/6/9 rendered pages on one A4-landscape sheet.
/// Output is raster (each page rendered to an image at 130 dpi) — text is no
/// longer selectable, but the layout is exact.
class NupScreen extends StatefulWidget {
  const NupScreen({super.key});

  @override
  State<NupScreen> createState() => _NupScreenState();
}

class _NupScreenState extends State<NupScreen> {
  File? _input;
  int _pageCount = 0;
  int _perSheet = 4;
  bool _running = false;
  File? _output;
  String? _error;

  static const _dpi = 130;
  // A4 landscape at _dpi: 297x210 mm.
  static const _sheetW = 1722; // 297mm * dpi/25.4
  static const _sheetH = 1219;
  static const _pad = 24;

  static const _layouts = {2: (2, 1), 4: (2, 2), 6: (3, 2), 9: (3, 3)};

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    final f = files.first;
    int count = 0;
    try {
      count = (await PdfEngine.instance.pageInfo(f)).length;
    } catch (_) {}
    setState(() {
      _input = f;
      _pageCount = count;
      _output = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null || _pageCount == 0) return;
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final (cols, rows) = _layouts[_perSheet]!;
      final cellW = (_sheetW - _pad * (cols + 1)) ~/ cols;
      final cellH = (_sheetH - _pad * (rows + 1)) ~/ rows;

      final sheets = <img.Image>[];
      var sheet = img.Image(width: _sheetW, height: _sheetH);
      img.fill(sheet, color: img.ColorRgb8(255, 255, 255));
      var slot = 0;
      for (var p = 0; p < _pageCount; p++) {
        final bmp = await PdfEngine.instance.pageBitmap(
          input,
          p,
          dpi: _dpi,
        );
        final decoded = img.decodePng(bmp.bytes);
        if (decoded != null) {
          final resized = img.copyResize(
            decoded,
            width: cellW,
            height: cellH,
            maintainAspect: true,
          );
          final col = slot % cols;
          final row = slot ~/ cols;
          final x = _pad + col * (cellW + _pad) + (cellW - resized.width) ~/ 2;
          final y = _pad + row * (cellH + _pad) + (cellH - resized.height) ~/ 2;
          img.compositeImage(sheet, resized, dstX: x, dstY: y);
        }
        slot++;
        if (slot == _perSheet || p == _pageCount - 1) {
          sheets.add(sheet);
          sheet = img.Image(width: _sheetW, height: _sheetH);
          img.fill(sheet, color: img.ColorRgb8(255, 255, 255));
          slot = 0;
        }
      }

      final dir = await outputsDir();
      final pngs = <File>[];
      for (var i = 0; i < sheets.length; i++) {
        final f = File(
          '${dir.path}/nup_sheet${i + 1}_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await f.writeAsBytes(Uint8List.fromList(img.encodePng(sheets[i])));
        pngs.add(f);
      }
      final out = await outputFile(
        '${fileBaseName(input.path)}_nup',
        'pdf',
      );
      await PdfEngine.instance.imagesToPdf(pngs, out);
      for (final f in pngs) {
        f.deleteSync();
      }
      setState(() => _output = out);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('N-up (gộp trang)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
            trailing: _pageCount > 0
                ? Chip(label: Text('$_pageCount trang'))
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            'Số trang mỗi tờ A4 ngang:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 6, label: Text('6')),
              ButtonSegment(value: 9, label: Text('9')),
            ],
            selected: {_perSheet},
            onSelectionChanged: (s) => setState(() => _perSheet = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'Lưu ý: output là PDF dạng ảnh (không chọn được text).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          RunButton(
            label: 'Gộp trang',
            onPressed: _run,
            enabled: !_running && _input != null && _pageCount > 0,
          ),
          const SizedBox(height: 16),
          if (_running)
            RunningPane(
              message: 'Đang render $_pageCount trang và gộp…',
            ),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
