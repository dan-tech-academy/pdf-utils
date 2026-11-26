import 'dart:io';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

class PdfToImagesScreen extends StatefulWidget {
  const PdfToImagesScreen({super.key});

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  File? _input;
  int _dpi = 150;
  bool _running = false;
  List<File>? _outputs;
  String? _error;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    setState(() {
      _input = files.first;
      _outputs = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null) return;
    setState(() {
      _running = true;
      _error = null;
      _outputs = null;
    });
    try {
      final dir = await outputsDir();
      final base =
          input.path.split('/').last.replaceAll(RegExp(r'\.pdf$'), '');
      final files = await PdfEngine.instance
          .renderToPngs(input, dir, base, dpi: _dpi);
      setState(() => _outputs = files);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Độ phân giải: $_dpi dpi (mỗi trang → 1 file PNG)'),
          Slider(
            value: _dpi.toDouble(),
            min: 72,
            max: 300,
            divisions: 3,
            onChanged: (v) => setState(() => _dpi = v.round()),
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang render…')
          else
            RunButton(
              label: 'Xuất ảnh',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_outputs != null) ResultFilesCard(files: _outputs!),
        ],
      ),
    );
  }
}
