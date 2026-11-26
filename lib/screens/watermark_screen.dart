import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../page_overlay.dart';
import '../widgets.dart';

/// Stamps a text watermark in the middle of every page. The text is drawn
/// with the app font and stamped as an image, because the engine's PDF
/// fonts cannot draw Vietnamese.
class WatermarkScreen extends StatefulWidget {
  const WatermarkScreen({super.key});

  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

/// The watermark may cover at most this share of the page in each direction.
const _maxCover = 0.85;

class _WatermarkScreenState extends State<WatermarkScreen> {
  File? _input;
  Uint8List? _firstPage;
  PageGeometry? _firstGeometry;
  final _text = TextEditingController(text: 'BẢN SAO');
  int _color = 0;
  bool _diagonal = true;
  double _fontSize = 60;
  double _opacity = 0.3;
  bool _running = false;
  File? _output;
  String? _error;

  // Ink colours of the stamp itself, not UI colours.
  static const _colors = <(String, Color)>[
    ('Xám', Color(0xFF7A7A7A)),
    ('Đỏ', Color(0xFFD32F2F)),
    ('Đen', Color(0xFF000000)),
  ];

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_running) return;
    try {
      final files = await pickPdfs();
      if (!mounted || files == null || files.isEmpty) return;
      final file = files.first;
      setState(() {
        _input = file;
        _firstPage = null;
        _firstGeometry = null;
        _output = null;
        _error = null;
      });
      final engine = PdfEngine.instance;
      final pages = await engine.pageInfo(file);
      if (pages.isEmpty) {
        if (mounted) setState(() => _error = 'File này không có trang nào.');
        return;
      }
      final bitmap = await engine.pageBitmap(file, 0, dpi: 50);
      if (!mounted || _input != file) return;
      setState(() {
        _firstGeometry = PageGeometry(pages.first);
        _firstPage = bitmap.bytes;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _run() async {
    final input = _input;
    // Read every option now: they must not change while the run awaits.
    final text = _text.text.trim();
    final fontSize = _fontSize;
    final color = _colors[_color].$2;
    final angle = _diagonal ? 45.0 : 0.0;
    final opacity = _opacity;
    if (input == null || _running) return;
    if (text.isEmpty) {
      setState(() => _error = 'Hãy nhập chữ cần đóng dấu.');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    File? out;
    try {
      final engine = PdfEngine.instance;
      final stamp = await renderTextImage(
        text,
        fontSize: fontSize,
        color: color,
        angleDegrees: angle,
      );
      // Pages with the same box and rotation share one embedded image.
      final groups = <String, (PageGeometry, List<int>)>{};
      final pages = await engine.pageInfo(input);
      for (var i = 0; i < pages.length; i++) {
        final g = PageGeometry(pages[i]);
        final key =
            '${g.box.x},${g.box.y},${g.box.width},${g.box.height},'
            '${g.quarterTurns}';
        groups.putIfAbsent(key, () => (g, <int>[])).$2.add(i);
      }
      final stamps = <ImageStamp>[];
      for (final (g, indices) in groups.values) {
        final fit = _fitScale(g, stamp.width, stamp.height);
        final w = stamp.width * fit;
        final h = stamp.height * fit;
        stamps.add((
          png: await g.uprightForPage(stamp.png),
          bounds: g.toPdf(
            Rect.fromLTWH((g.width - w) / 2, (g.height - h) / 2, w, h),
          ),
          pages: indices,
          opacity: opacity,
        ));
      }
      out = await outputFile('${fileBaseName(input.path)}_dongdau', 'pdf');
      await engine.addImageStamps(input, out, stamps);
      if (mounted) setState(() => _output = out);
    } catch (e) {
      deleteQuietly(out);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _firstPage;
    final geometry = _firstGeometry;
    return Scaffold(
      appBar: AppBar(title: const Text('Đóng dấu chữ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'In một dòng chữ mờ lên giữa mọi trang, vd: BẢN SAO, MẬT, NỘI BỘ.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            enabled: !_running,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Chữ đóng dấu'),
          ),
          const SizedBox(height: 16),
          _OptionRow(
            label: 'Màu',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _colors.length; i++)
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: _colors[i].$2),
                    label: Text(_colors[i].$1),
                    selected: _color == i,
                    onSelected: _running
                        ? null
                        : (_) => setState(() => _color = i),
                  ),
              ],
            ),
          ),
          _OptionRow(
            label: 'Hướng chữ',
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Chéo')),
                ButtonSegment(value: false, label: Text('Ngang')),
              ],
              selected: {_diagonal},
              onSelectionChanged: _running
                  ? null
                  : (s) => setState(() => _diagonal = s.first),
            ),
          ),
          _OptionRow(
            label: 'Cỡ chữ',
            child: SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 36, label: Text('Nhỏ')),
                ButtonSegment(value: 60, label: Text('Vừa')),
                ButtonSegment(value: 96, label: Text('Lớn')),
              ],
              selected: {_fontSize},
              onSelectionChanged: _running
                  ? null
                  : (s) => setState(() => _fontSize = s.first),
            ),
          ),
          _OptionRow(
            label: 'Độ đậm',
            child: SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 0.15, label: Text('Nhạt')),
                ButtonSegment(value: 0.3, label: Text('Vừa')),
                ButtonSegment(value: 0.6, label: Text('Đậm')),
              ],
              selected: {_opacity},
              onSelectionChanged: _running
                  ? null
                  : (s) => setState(() => _opacity = s.first),
            ),
          ),
          if (preview != null && geometry != null) ...[
            const SizedBox(height: 8),
            Text('Xem trước trang đầu', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: _Preview(
                  page: preview,
                  geometry: geometry,
                  text: _text.text.trim(),
                  fontSize: _fontSize,
                  color: _colors[_color].$2,
                  opacity: _opacity,
                  diagonal: _diagonal,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang đóng dấu…')
          else
            RunButton(
              label: 'Đóng dấu',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}

/// How far a stamp of [width] × [height] points must shrink to fit a page.
double _fitScale(PageGeometry g, double width, double height) => math.min(
  1,
  math.min(g.width * _maxCover / width, g.height * _maxCover / height),
);

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// The first page with the watermark drawn the way it will be stamped.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.page,
    required this.geometry,
    required this.text,
    required this.fontSize,
    required this.color,
    required this.opacity,
    required this.diagonal,
  });

  final Uint8List page;
  final PageGeometry geometry;
  final String text;
  final double fontSize;
  final Color color;
  final double opacity;
  final bool diagonal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: geometry.width / geometry.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / geometry.width;
            TextStyle style(double size) => TextStyle(
              fontFamily: 'BeVietnamPro',
              fontSize: size,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.2,
            );
            // Same box maths as the stamp, so the preview matches the file.
            final painter = TextPainter(
              text: TextSpan(text: text, style: style(fontSize)),
              textDirection: TextDirection.ltr,
            )..layout();
            final rad = diagonal ? math.pi / 4 : 0.0;
            final boxW =
                painter.width * math.cos(rad) + painter.height * math.sin(rad);
            final boxH =
                painter.width * math.sin(rad) + painter.height * math.cos(rad);
            painter.dispose();
            final fit = text.isEmpty ? 1.0 : _fitScale(geometry, boxW, boxH);
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(page, fit: BoxFit.fill, gaplessPlayback: true),
                  Center(
                    child: Transform.rotate(
                      angle: -rad,
                      child: Opacity(
                        opacity: opacity,
                        child: Text(
                          text,
                          maxLines: 1,
                          softWrap: false,
                          textScaler: TextScaler.noScaling,
                          style: style(fontSize * fit * scale),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
