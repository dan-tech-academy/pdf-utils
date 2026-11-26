import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

/// Converts a PDF to PDF/A-2b, the long-term archiving standard that
/// e-government portals often ask for, and says whether the result passes.
class PdfaScreen extends StatefulWidget {
  const PdfaScreen({super.key});

  @override
  State<PdfaScreen> createState() => _PdfaScreenState();
}

class _PdfaScreenState extends State<PdfaScreen> {
  File? _input;
  bool _running = false;
  File? _output;
  PdfValidationReport? _report;
  String? _error;

  Future<void> _pick() async {
    // A new file mid-run would end up shown with the old file's result.
    if (_running) return;
    final files = await pickPdfs();
    if (!mounted || _running || files == null || files.isEmpty) return;
    setState(() {
      _input = files.first;
      _output = null;
      _report = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null || _running) return;
    setState(() {
      _running = true;
      _error = null;
      _output = null;
      _report = null;
    });
    File? out;
    try {
      out = await outputFile('${fileBaseName(input.path)}_pdfa', 'pdf');
      final report = await PdfEngine.instance.convertToPdfA(input, out);
      if (!mounted) return;
      setState(() {
        _output = out;
        _report = report;
      });
    } catch (e) {
      deleteQuietly(out);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  static String _verdict(PdfValidationReport report) {
    if (report.isCompliant) return 'Đạt chuẩn PDF/A-2b';
    if (report.errorCount > 0) {
      return 'Đã chuyển, còn ${report.errorCount} điểm chưa đạt chuẩn';
    }
    return 'Đã chuyển, chưa đạt chuẩn hoàn toàn';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('PDF/A (lưu trữ)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Chuẩn lưu trữ lâu dài, thường được yêu cầu khi nộp hồ sơ '
            'điện tử.',
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
          if (_running)
            const RunningPane(message: 'Đang chuyển sang PDF/A…')
          else
            RunButton(
              label: 'Chuyển sang PDF/A',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null && _report != null)
            ResultCard(file: _output!, extra: _verdict(_report!)),
        ],
      ),
    );
  }
}
