import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

/// Rewrites a damaged PDF so it opens again. The engine rebuilds a broken
/// cross-reference table while reading, so a full re-save recovers files
/// with bad offsets or a cut-off tail.
class RepairScreen extends StatefulWidget {
  const RepairScreen({super.key});

  @override
  State<RepairScreen> createState() => _RepairScreenState();
}

class _RepairScreenState extends State<RepairScreen> {
  static const _tooDamaged =
      'File bị hỏng quá nặng nên không khôi phục được. '
      'Hãy xin lại file gốc từ người gửi.';

  File? _input;
  bool _running = false;
  File? _output;
  int _pageCount = 0;
  String? _error;

  Future<void> _pick() async {
    // A new file mid-run would end up shown with the old file's result.
    if (_running) return;
    final files = await pickPdfs();
    if (!mounted || _running || files == null || files.isEmpty) return;
    setState(() {
      _input = files.first;
      _output = null;
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
    });
    File? out;
    try {
      out = await outputFile('${fileBaseName(input.path)}_dasua', 'pdf');
      await PdfEngine.instance.repair(input, out);
      final pages = (await PdfEngine.instance.pageInfo(out)).length;
      if (pages == 0) {
        // A file with no readable page is not a recovery.
        deleteQuietly(out);
        if (mounted) setState(() => _error = _tooDamaged);
        return;
      }
      if (!mounted) return;
      setState(() {
        _output = out;
        _pageCount = pages;
      });
    } catch (e) {
      deleteQuietly(out);
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Damage inside the file gets the plain "too damaged" answer; a locked
  /// file or a storage problem keeps its own hint.
  static String _messageFor(Object error) => switch (error) {
    PdfPasswordRequired() ||
    PdfWrongPassword() ||
    PdfCryptoFailed() ||
    PdfIoFailed() => friendlyError(error),
    PdfError() => _tooDamaged,
    _ => friendlyError(error),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sửa PDF lỗi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Dùng khi file PDF không mở được hoặc báo lỗi.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF bị lỗi',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang sửa file…')
          else
            RunButton(
              label: 'Sửa file',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null)
            ResultCard(file: _output!, extra: 'Đã khôi phục $_pageCount trang'),
        ],
      ),
    );
  }
}
