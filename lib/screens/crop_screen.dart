import 'dart:io';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// Crops page margins — 4 sliders in millimetres applied to every page.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  File? _input;
  double _left = 0;
  double _right = 0;
  double _top = 0;
  double _bottom = 0;
  bool _running = false;
  File? _output;
  String? _error;

  static const _mmToPt = 72 / 25.4;

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
    if (input == null) return;
    if (_left == 0 && _right == 0 && _top == 0 && _bottom == 0) {
      setState(() => _error = 'Chọn ít nhất một lề để cắt');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final out = await outputFile(
        '${fileBaseName(input.path)}_cat',
        'pdf',
      );
      await PdfEngine.instance.cropMargins(
        input,
        out,
        left: _left * _mmToPt,
        right: _right * _mmToPt,
        top: _top * _mmToPt,
        bottom: _bottom * _mmToPt,
      );
      setState(() => _output = out);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  Widget _slider(String label, double value, void Function(double) onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${value.toStringAsFixed(0)} mm'),
          Slider(
            value: value,
            min: 0,
            max: 60,
            divisions: 60,
            onChanged: onChanged,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cắt lề trang')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf,
            label: 'Chọn PDF',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
          ),
          const SizedBox(height: 8),
          _slider('Lề trái', _left, (v) => setState(() => _left = v)),
          _slider('Lề phải', _right, (v) => setState(() => _right = v)),
          _slider('Lề trên', _top, (v) => setState(() => _top = v)),
          _slider('Lề dưới', _bottom, (v) => setState(() => _bottom = v)),
          const SizedBox(height: 8),
          RunButton(
            label: 'Cắt lề',
            onPressed: _run,
            enabled: !_running && _input != null,
          ),
          const SizedBox(height: 16),
          if (_running) const RunningPane(message: 'Đang cắt lề…'),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
