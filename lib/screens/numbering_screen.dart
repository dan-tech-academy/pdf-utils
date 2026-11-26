import 'dart:io';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../page_overlay.dart';
import '../widgets.dart';

/// Page numbering / header-footer: stamps a short text (e.g. "Trang 3 / 10")
/// at a chosen spot of every page. The text is drawn with the app font and
/// stamped as an image, so Vietnamese patterns render correctly.
class NumberingScreen extends StatefulWidget {
  const NumberingScreen({super.key});

  @override
  State<NumberingScreen> createState() => _NumberingScreenState();
}

enum _Spot {
  bottomCenter('Giữa, cuối trang'),
  topCenter('Giữa, đầu trang'),
  bottomRight('Góc dưới phải'),
  topRight('Góc trên phải'),
  bottomLeft('Góc dưới trái'),
  topLeft('Góc trên trái');

  const _Spot(this.label);
  final String label;
}

/// Distance from the page edge, in points (about 8.5 mm).
const _margin = 24.0;

/// [pattern] for page [page] of [count]: `{i}` and `{n}` filled in.
String _textFor(String pattern, int page, int count) =>
    pattern.replaceAll('{i}', '$page').replaceAll('{n}', '$count');

/// Where a [w] × [h] label goes at [spot] on a page, in display points.
Rect _spotRect(_Spot spot, PageGeometry g, double w, double h) {
  final left = switch (spot) {
    _Spot.bottomCenter || _Spot.topCenter => (g.width - w) / 2,
    _Spot.bottomRight || _Spot.topRight => g.width - _margin - w,
    _Spot.bottomLeft || _Spot.topLeft => _margin,
  };
  final top = switch (spot) {
    _Spot.topCenter || _Spot.topRight || _Spot.topLeft => _margin,
    _ => g.height - _margin - h,
  };
  return Rect.fromLTWH(left, top, w, h);
}

class _NumberingScreenState extends State<NumberingScreen> {
  File? _input;
  int _pageCount = 0;
  final _pattern = TextEditingController(text: '{i}');
  _Spot _spot = _Spot.bottomCenter;
  double _fontSize = 12;
  bool _skipFirst = false;
  bool _running = false;
  File? _output;
  String? _error;

  /// Ready-made patterns, shown as they look on page 1 of 10.
  static const _presets = <(String, String)>[
    ('1', '{i}'),
    ('Trang 1', 'Trang {i}'),
    ('1/10', '{i}/{n}'),
    ('Trang 1/10', 'Trang {i}/{n}'),
  ];

  @override
  void initState() {
    super.initState();
    _pattern.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_running) return;
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    final f = files.first;
    var count = 0;
    try {
      count = (await PdfEngine.instance.pageInfo(f)).length;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _input = f;
      _pageCount = count;
      _output = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    // Read every option now: they must not change while the run awaits.
    final pattern = _pattern.text.trim();
    final fontSize = _fontSize;
    final spot = _spot;
    final skipFirst = _skipFirst;
    if (input == null || _running) return;
    if (pattern.isEmpty) {
      setState(() => _error = 'Hãy chọn hoặc nhập kiểu số trang.');
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
      final pages = await engine.pageInfo(input);
      final stamps = <ImageStamp>[];
      for (var i = skipFirst ? 1 : 0; i < pages.length; i++) {
        final g = PageGeometry(pages[i]);
        final label = await renderTextImage(
          _textFor(pattern, i + 1, pages.length),
          fontSize: fontSize,
          color: const Color(0xFF000000),
          fontWeight: FontWeight.w500,
        );
        stamps.add((
          png: await g.uprightForPage(label.png),
          bounds: g.toPdf(_spotRect(spot, g, label.width, label.height)),
          pages: [i],
          opacity: 1.0,
        ));
      }
      out = await outputFile('${fileBaseName(input.path)}_sotrang', 'pdf');
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
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final pattern = _pattern.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Đánh số trang')),
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
          const SizedBox(height: 16),
          Text('Kiểu số trang', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (example, value) in _presets)
                ChoiceChip(
                  label: Text(example),
                  selected: pattern == value,
                  onSelected: _running ? null : (_) => _pattern.text = value,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pattern,
            enabled: !_running,
            decoration: const InputDecoration(
              labelText: 'Hoặc tự nhập',
              helperText: '{i} là số trang, {n} là tổng số trang',
            ),
          ),
          if (pattern.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Ví dụ, trang 3 sẽ ghi: '
              '${_textFor(pattern, 3, _pageCount > 0 ? _pageCount : 10)}',
              style: muted,
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<_Spot>(
            initialValue: _spot,
            decoration: const InputDecoration(labelText: 'Vị trí'),
            items: [
              for (final s in _Spot.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: _running ? null : (v) => setState(() => _spot = v!),
          ),
          const SizedBox(height: 16),
          Text('Cỡ chữ', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 10, label: Text('Nhỏ')),
              ButtonSegment(value: 12, label: Text('Vừa')),
              ButtonSegment(value: 14, label: Text('Lớn')),
            ],
            selected: {_fontSize},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() => _fontSize = s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bỏ qua trang đầu'),
            subtitle: const Text('Trang bìa không ghi số, trang 2 ghi số 2'),
            value: _skipFirst,
            onChanged: _running ? null : (v) => setState(() => _skipFirst = v),
          ),
          const SizedBox(height: 8),
          if (_running)
            const RunningPane(message: 'Đang đánh số trang…')
          else
            RunButton(
              label: 'Đánh số trang',
              onPressed: _run,
              enabled: _input != null,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
