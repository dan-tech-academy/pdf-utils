import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// View & edit document metadata.
class MetadataScreen extends StatefulWidget {
  const MetadataScreen({super.key});

  @override
  State<MetadataScreen> createState() => _MetadataScreenState();
}

class _MetadataScreenState extends State<MetadataScreen> {
  File? _input;
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _subject = TextEditingController();
  final _keywords = TextEditingController();
  int? _pageCount;
  String? _version;
  bool _running = false;
  File? _output;
  String? _error;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    final f = files.first;
    setState(() {
      _input = f;
      _output = null;
      _error = null;
    });
    try {
      final info = await PdfEngine.instance.info(f);
      final m = info.metadata;
      setState(() {
        _pageCount = info.pageCount;
        _version = info.version;
        _title.text = m.title ?? '';
        _author.text = m.author ?? '';
        _subject.text = m.subject ?? '';
        _keywords.text = m.keywords ?? '';
      });
    } catch (_) {}
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
      final out = await outputFile(
        '${input.path.split('/').last}_meta',
        'pdf',
      );
      await PdfEngine.instance.setMetadata(
        input,
        out,
        PdfMetadata(
          title: _title.text.trim().isEmpty ? null : _title.text.trim(),
          author: _author.text.trim().isEmpty ? null : _author.text.trim(),
          subject:
              _subject.text.trim().isEmpty ? null : _subject.text.trim(),
          keywords:
              _keywords.text.trim().isEmpty ? null : _keywords.text.trim(),
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
      appBar: AppBar(title: const Text('Metadata')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF',
            picked: _input?.path.split('/').last,
            onPick: _pick,
            trailing: _pageCount == null
                ? null
                : Text('$_pageCount trang · v$_version'),
          ),
          const SizedBox(height: 16),
          if (_input != null) ...[
            for (final (label, ctrl) in [
              ('Tiêu đề', _title),
              ('Tác giả', _author),
              ('Chủ đề', _subject),
              ('Từ khóa', _keywords),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: ctrl,
                  decoration: InputDecoration(labelText: label),
                ),
              ),
          ],
          if (_running)
            const RunningPane(message: 'Đang lưu…')
          else
            RunButton(
              label: 'Lưu metadata',
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
