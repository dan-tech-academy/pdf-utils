import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../errors.dart';
import '../files.dart';
import '../page_text.dart';
import '../pdf_ocr.dart';
import '../summarizer.dart';
import '../widgets.dart';

/// Picks the key sentences of a PDF on the device, for copy, share or .txt.
/// A scanned PDF has its text recognized first.
class SummarizeScreen extends StatefulWidget {
  const SummarizeScreen({super.key});

  @override
  State<SummarizeScreen> createState() => _SummarizeScreenState();
}

/// Ranks sentences in a background isolate. Top-level, so the isolate
/// closure captures only the text and the count.
Future<List<String>> _summarizeInBackground(String text, int maxSentences) =>
    Isolate.run(() => summarize(text, maxSentences: maxSentences));

/// The summary as plain text: one bullet per line.
String _asText(List<String> sentences) =>
    sentences.map((s) => '• $s').join('\n');

class _SummarizeScreenState extends State<SummarizeScreen> {
  File? _input;

  /// Text of [_input], kept so trying another length skips the reading (and
  /// a scan's recognition).
  String? _text;

  /// Whether [_text] was recognized on the pages of a scan.
  bool _scanned = false;
  int _length = 10;
  bool _running = false;
  bool _cancelRequested = false;

  /// Progress while the file is read as a scan; null otherwise.
  String? _scanStatus;
  List<String>? _summary;
  File? _output;
  String? _error;

  static const _lengths = <(String, int)>[
    ('Ngắn', 5),
    ('Vừa', 10),
    ('Chi tiết', 20),
  ];

  /// True once the user pressed Hủy or left the screen.
  bool get _stopped => _cancelRequested || !mounted;

  Future<void> _pick() async {
    if (_running) return;
    try {
      final file = await pickPdfOrText();
      if (file == null || !mounted) return;
      setState(() {
        _input = file;
        _text = null;
        _scanned = false;
        _summary = null;
        _output = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Hủy is offered while a scan is recognized, and takes effect after the
  /// page being read.
  void _cancel() => setState(() {
    _cancelRequested = true;
    _scanStatus = 'Đang dừng…';
  });

  Future<void> _run() async {
    final input = _input;
    if (input == null || _running) return;
    final length = _length;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _scanStatus = null;
      _error = null;
      _summary = null;
      _output = null;
    });
    try {
      var text = _text;
      if (text == null) {
        final read = await readOrRecognizePages(
          input,
          onScanProgress: (done, total) {
            if (!_stopped) {
              setState(
                () => _scanStatus = scanProgressText('File', done, total),
              );
            }
          },
          isCancelled: () => _stopped,
        );
        if (read == null || !mounted) return;
        text = joinPages(read.pages);
        _text = text;
        _scanned = read.scanned;
        if (_stopped) return;
        if (read.scanned) setState(() => _scanStatus = null);
      }
      if (text.trim().isEmpty) {
        setState(
          () => _error = _scanned
              ? 'Không tìm thấy chữ nào trong file, kể cả khi đọc như bản '
                    'scan. Có thể file chỉ có hình, hoặc chữ quá mờ.'
              : 'File này không có chữ nào để tóm tắt.',
        );
        return;
      }
      final summary = await _summarizeInBackground(text, length);
      if (!mounted) return;
      setState(() {
        if (summary.isEmpty) {
          _error =
              'File này không có đoạn văn nào đủ dài để tóm tắt (có thể chỉ '
              'có bảng hoặc tiêu đề).';
        } else {
          _summary = summary;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _scanStatus = null;
        });
      }
    }
  }

  Future<void> _copy(List<String> summary) async {
    try {
      await copyText(context, _asText(summary));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _share(List<String> summary) async {
    final input = _input;
    if (input == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _asText(summary),
          subject: 'Tóm tắt ${fileBaseName(input.path)}',
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _save(List<String> summary) async {
    final input = _input;
    if (input == null) return;
    File? out;
    try {
      out = await outputFile('${fileBaseName(input.path)}_tomtat', 'txt');
      await out.writeAsString(_asText(summary));
      if (!mounted) return;
      setState(() => _output = out);
    } catch (e) {
      deleteQuietly(out);
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Tóm tắt PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Chọn ra những câu quan trọng nhất trong file, chạy ngay trên máy.',
            style: muted,
          ),
          const SizedBox(height: 12),
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF (hoặc file .txt) cần tóm tắt',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
          ),
          const SizedBox(height: 16),
          Text('Độ dài', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final (label, count) in _lengths)
                ButtonSegment(value: count, label: Text(label)),
            ],
            selected: {_length},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() {
                    _length = s.first;
                    _summary = null;
                    _output = null;
                  }),
          ),
          const SizedBox(height: 6),
          Text('Tối đa $_length câu', style: muted),
          const SizedBox(height: 16),
          if (_running)
            RunningPane(
              message: _scanStatus ?? 'Đang tóm tắt…',
              onCancel: _scanStatus == null || _cancelRequested
                  ? null
                  : _cancel,
            )
          else
            RunButton(
              label: 'Tóm tắt',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (summary != null) ...[
            if (_scanned) ...[
              Text(scannedTextNote, style: muted),
              const SizedBox(height: 8),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${summary.length} câu quan trọng nhất',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final sentence in summary)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•'),
                            const SizedBox(width: 10),
                            Expanded(child: Text(sentence)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Sao chép'),
                  onPressed: () => _copy(summary),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Chia sẻ'),
                  onPressed: () => _share(summary),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Lưu .txt'),
                  onPressed: () => _save(summary),
                ),
              ],
            ),
          ],
          if (_output != null) ...[
            const SizedBox(height: 8),
            ResultCard(file: _output!),
          ],
        ],
      ),
    );
  }
}
