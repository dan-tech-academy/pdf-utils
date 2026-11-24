import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

class WatermarkScreen extends StatefulWidget {
  const WatermarkScreen({super.key});

  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends State<WatermarkScreen> {
  File? _input;
  final _text = TextEditingController(text: 'CONFIDENTIAL');
  double _fontSize = 48;
  double _opacity = 0.3;
  double _angle = 45;
  PdfColor _color = PdfColor.gray;
  bool _running = false;
  File? _output;
  String? _error;

  static const _colors = <String, PdfColor>{
    'Xám': PdfColor.gray,
    'Đỏ': PdfColor.red,
    'Đen': PdfColor.black,
  };

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    setState(() {
      _input = files.first;
      _output = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null || _text.text.trim().isEmpty) return;
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final out = await outputFile(
        '${input.path.split('/').last}_watermark',
        'pdf',
      );
      await PdfEngine.instance.addWatermark(
        input,
        out,
        _text.text.trim(),
        style: PdfWatermarkStyle(
          fontSize: _fontSize,
          opacity: _opacity,
          angleDegrees: _angle,
          color: _color,
        ),
      );
      setState(() => _output = out);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Watermark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf,
            label: 'Chọn PDF',
            picked: _input?.path.split('/').last,
            onPick: _pick,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            decoration: const InputDecoration(
              labelText: 'Nội dung watermark',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('Cỡ chữ: ${_fontSize.round()}pt'),
          Slider(
            value: _fontSize,
            min: 12,
            max: 120,
            divisions: 18,
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          Text('Độ mờ: ${(_opacity * 100).round()}%'),
          Slider(
            value: _opacity,
            min: 0.05,
            max: 1.0,
            divisions: 19,
            onChanged: (v) => setState(() => _opacity = v),
          ),
          Text('Góc nghiêng: ${_angle.round()}°'),
          Slider(
            value: _angle,
            min: -90,
            max: 90,
            divisions: 12,
            onChanged: (v) => setState(() => _angle = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final e in _colors.entries)
                ChoiceChip(
                  label: Text(e.key),
                  selected: _color == e.value,
                  onSelected: (_) => setState(() => _color = e.value),
                ),
            ],
          ),
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
