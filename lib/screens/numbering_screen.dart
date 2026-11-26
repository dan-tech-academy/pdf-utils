import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// Page numbering / header-footer: stamps a small text (e.g. "Trang 3 / 10")
/// at a chosen corner of every page.
class NumberingScreen extends StatefulWidget {
  const NumberingScreen({super.key});

  @override
  State<NumberingScreen> createState() => _NumberingScreenState();
}

class _NumberingScreenState extends State<NumberingScreen> {
  File? _input;
  int _pageCount = 0;
  final _pattern = TextEditingController(text: 'Trang {i} / {n}');
  PdfCorner _corner = PdfCorner.bottomRight;
  double _fontSize = 11;
  double _margin = 16;
  bool _running = false;
  File? _output;
  String? _error;

  static const _corners = {
    PdfCorner.topLeft: 'Trên trái',
    PdfCorner.topRight: 'Trên phải',
    PdfCorner.bottomLeft: 'Dưới trái',
    PdfCorner.bottomRight: 'Dưới phải',
  };

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
    if (input == null || _pattern.text.trim().isEmpty) return;
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final out = await outputFile(
        '${fileBaseName(input.path)}_sotrang',
        'pdf',
      );
      await PdfEngine.instance.numberPages(
        input,
        out,
        pattern: _pattern.text.trim(),
        position: PdfWatermarkPosition.corner(
          _corner,
          marginX: _margin,
          marginY: _margin,
        ),
        fontSize: _fontSize,
      );
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
          const SizedBox(height: 12),
          TextField(
            controller: _pattern,
            decoration: const InputDecoration(
              labelText: 'Mẫu chữ',
              hintText: 'Trang {i} / {n}',
              helperText: '{i} = số trang, {n} = tổng số trang',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PdfCorner>(
            initialValue: _corner,
            decoration: const InputDecoration(labelText: 'Vị trí'),
            items: [
              for (final e in _corners.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _corner = v!),
          ),
          const SizedBox(height: 8),
          Text('Cỡ chữ: ${_fontSize.toStringAsFixed(0)} pt'),
          Slider(
            value: _fontSize,
            min: 8,
            max: 24,
            divisions: 16,
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          Text('Lề: ${_margin.toStringAsFixed(0)} pt'),
          Slider(
            value: _margin,
            min: 8,
            max: 60,
            divisions: 26,
            onChanged: (v) => setState(() => _margin = v),
          ),
          const SizedBox(height: 8),
          RunButton(
            label: 'Đánh số trang',
            onPressed: _run,
            enabled: !_running && _input != null,
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang đánh số trang…'),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
