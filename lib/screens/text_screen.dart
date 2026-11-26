import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

/// Extract all text from a PDF; preview + save as plain text (.txt) or as
/// Markdown (.md), which keeps headings, lists and tables.
class TextScreen extends StatefulWidget {
  const TextScreen({super.key});

  @override
  State<TextScreen> createState() => _TextScreenState();
}

class _TextScreenState extends State<TextScreen> {
  File? _input;
  PdfExtractionFormat _format = PdfExtractionFormat.plain;
  bool _running = false;
  String? _text;
  File? _output;
  String? _error;

  Future<void> _pick() async {
    if (_running) return;
    try {
      final files = await pickPdfs();
      if (!mounted || files == null || files.isEmpty) return;
      setState(() {
        _input = files.first;
        _text = null;
        _output = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Whitespace and Markdown syntax: what a Markdown extraction of a page
  /// without text (a scan) still contains, such as page rules.
  static final _noText = RegExp(r'[\s\-#*_>|=`!\[\]()]');

  Future<void> _run() async {
    final input = _input;
    if (input == null || _running) return;
    final format = _format;
    setState(() {
      _running = true;
      _error = null;
      _text = null;
      _output = null;
    });
    try {
      final text =
          await PdfEngine.instance.extractText(input, format: format);
      if (text.replaceAll(_noText, '').isEmpty) {
        if (mounted) {
          setState(() => _error =
              'Không tìm thấy chữ trong file này (có thể là bản scan). '
              'Hãy dùng công cụ "Nhận dạng chữ (OCR)".');
        }
        return;
      }
      final out = await outputFile(
        '${input.path.split('/').last}_text',
        format == PdfExtractionFormat.markdown ? 'md' : 'txt',
      );
      await out.writeAsString(text);
      if (!mounted) return;
      setState(() {
        _text = text;
        _output = out;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trích xuất chữ')),
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
          Text(
            'Lưu dưới dạng',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<PdfExtractionFormat>(
            segments: const [
              ButtonSegment(
                value: PdfExtractionFormat.plain,
                label: Text('Văn bản (.txt)'),
              ),
              ButtonSegment(
                value: PdfExtractionFormat.markdown,
                label: Text('Markdown (.md)'),
              ),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          if (_format == PdfExtractionFormat.markdown) ...[
            const SizedBox(height: 8),
            Text(
              'Giữ tiêu đề, danh sách và bảng. Hợp để dán vào ChatGPT '
              'hoặc phần mềm ghi chú.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang trích xuất…')
          else
            RunButton(
              label: 'Trích xuất',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_text != null) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Sao chép'),
                onPressed: () => copyText(context, _text!),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _text!.length > 4000
                      ? '${_text!.substring(0, 4000)}\n…'
                      : _text!,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
