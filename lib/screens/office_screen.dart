import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// PDF ↔ Office (Word/Excel/PowerPoint) conversion.
class OfficeScreen extends StatefulWidget {
  const OfficeScreen({super.key});

  @override
  State<OfficeScreen> createState() => _OfficeScreenState();
}

class _OfficeScreenState extends State<OfficeScreen> {
  File? _input;
  PdfOfficeFormat _format = PdfOfficeFormat.docx;
  bool _running = false;
  File? _output;
  String? _error;

  static const _exts = {'docx': 'docx', 'xlsx': 'xlsx', 'pptx': 'pptx'};

  String get _inputExt =>
      _input?.path.split('.').last.toLowerCase() ?? '';

  bool get _isPdfInput => _inputExt == 'pdf';

  PdfOfficeFormat? get _inputOfficeFormat => switch (_inputExt) {
    'docx' => PdfOfficeFormat.docx,
    'xlsx' => PdfOfficeFormat.xlsx,
    'pptx' => PdfOfficeFormat.pptx,
    _ => null,
  };

  Future<void> _pick() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'xlsx', 'pptx'],
    );
    final path = picked?.path;
    if (path == null || !File(path).existsSync()) return;
    setState(() {
      _input = File(path);
      _output = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null) return;
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final base = fileBaseName(input.path).replaceAll(
        RegExp(r'\.(pdf|docx|xlsx|pptx)$'),
        '',
      );
      File out;
      if (_isPdfInput) {
        out = await outputFile('${base}_office', _format.wire);
        await PdfEngine.instance.pdfToOffice(input, out, _format);
      } else {
        final format = _inputOfficeFormat;
        if (format == null) {
          setState(() {
            _running = false;
            _error = 'File không phải PDF hoặc Office';
          });
          return;
        }
        out = await outputFile('${base}_pdf', 'pdf');
        await PdfEngine.instance.officeToPdf(input, out, format);
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
    final isPdf = _isPdfInput;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF ↔ Office')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.description,
            label: 'Chọn PDF hoặc file Office',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
            trailing: _input == null
                ? null
                : Chip(label: Text(_inputExt.toUpperCase())),
          ),
          if (isPdf) ...[
            const SizedBox(height: 12),
            Text(
              'Chuyển PDF sang:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<PdfOfficeFormat>(
              segments: const [
                ButtonSegment(
                  value: PdfOfficeFormat.docx,
                  label: Text('Word (.docx)'),
                  icon: Icon(Icons.article),
                ),
                ButtonSegment(
                  value: PdfOfficeFormat.xlsx,
                  label: Text('Excel (.xlsx)'),
                  icon: Icon(Icons.table_chart),
                ),
                ButtonSegment(
                  value: PdfOfficeFormat.pptx,
                  label: Text('PowerPoint'),
                  icon: Icon(Icons.slideshow),
                ),
              ],
              selected: {_format},
              onSelectionChanged: (s) =>
                  setState(() => _format = s.first),
            ),
          ],
          if (_input != null && !isPdf && _inputOfficeFormat != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'File ${_exts[_inputExt]} sẽ được chuyển thành PDF.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          RunButton(
            label: _isPdfInput ? 'Chuyển sang Office' : 'Chuyển sang PDF',
            onPressed: _run,
            enabled: !_running && _input != null,
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang chuyển đổi…'),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
