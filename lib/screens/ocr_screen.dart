import 'dart:io';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../page_text.dart';
import '../pdf_ocr.dart';
import '../widgets.dart';

/// OCR: recognizes text in picked images (or photos), or in the pages of a
/// scanned PDF, with ML Kit (`pdf_ocr.dart`) and shows the result for copy /
/// save as .txt. Latin script — covers Vietnamese.
class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  /// A longer result shows only its start on screen, because laying out a
  /// whole book in one text widget stalls the UI. Copy and save use all of
  /// it.
  static const _previewChars = 30000;

  List<File> _images = const [];
  File? _pdf;
  int _pdfPageCount = 0;
  bool _running = false;
  bool _cancelRequested = false;
  String _progress = '';
  String? _text;
  String? _notice;
  File? _output;
  String? _error;

  /// True once the user pressed Hủy or left the screen.
  bool get _stopped => _cancelRequested || !mounted;

  /// Makes [images] or [pdf] (with [pageCount] pages) the thing to read and
  /// clears the last result.
  void _setSource({
    List<File> images = const [],
    File? pdf,
    int pageCount = 0,
  }) {
    setState(() {
      _images = images;
      _pdf = pdf;
      _pdfPageCount = pageCount;
      _text = null;
      _notice = null;
      _output = null;
      _error = null;
    });
  }

  Future<void> _pickGallery() async {
    if (_running) return;
    try {
      final files = await pickImages();
      if (files == null || !mounted) return;
      _setSource(images: files);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _pickCamera() async {
    if (_running) return;
    try {
      final file = await capturePhoto();
      if (file == null || !mounted) return;
      _setSource(images: [file]);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _pickPdf() async {
    if (_running) return;
    try {
      final files = await pickPdfs();
      if (files == null || files.isEmpty) return;
      final pages = await PdfEngine.instance.pageInfo(files.first);
      if (!mounted) return;
      _setSource(pdf: files.first, pageCount: pages.length);
    } catch (e) {
      if (!mounted) return;
      _setSource();
      setState(() => _error = friendlyError(e));
    }
  }

  void _cancel() => setState(() {
    _cancelRequested = true;
    _progress = 'Đang dừng…';
  });

  Future<void> _run() async {
    final pdf = _pdf;
    final images = _images;
    final total = pdf != null ? _pdfPageCount : images.length;
    if (total == 0 || _running) return;
    final unit = pdf != null ? 'trang' : 'ảnh';
    setState(() {
      _running = true;
      _cancelRequested = false;
      _progress = total == 1
          ? 'Đang nhận dạng chữ…'
          : 'Đang nhận dạng $unit 1/$total';
      _error = null;
      _text = null;
      _notice = null;
      _output = null;
    });
    void progress(int done, int count) {
      if (count > 1 && !_stopped) {
        setState(() => _progress = 'Đang nhận dạng $unit ${done + 1}/$count');
      }
    }

    try {
      // Hủy takes effect between pages (or images): a page already being
      // read is finished first.
      final texts = pdf != null
          ? await recognizePdfPages(
              pdf,
              onProgress: progress,
              isCancelled: () => _stopped,
            )
          : await recognizeImages(
              images,
              onProgress: progress,
              isCancelled: () => _stopped,
            );
      if (!mounted) return;
      final done = texts.length;
      final parts = [
        for (var i = 0; i < done; i++)
          if (texts[i].isNotEmpty)
            pdf != null && total > 1
                ? '${pageMarker(i + 1)}\n${texts[i]}'
                : texts[i],
      ];
      if (parts.isEmpty) {
        if (done == total) {
          setState(
            () => _error = pdf != null
                ? 'Không nhận dạng được chữ nào trong file.'
                : 'Không nhận dạng được chữ nào trong ảnh.',
          );
        }
        return;
      }
      setState(() {
        _text = parts.join('\n\n');
        _notice = done < total ? 'Đã dừng sau $unit $done/$total.' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _copy() async {
    final text = _text;
    if (text == null) return;
    try {
      await copyText(context, text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _saveTxt() async {
    final text = _text;
    if (text == null || _output != null) return;
    final pdf = _pdf;
    File? out;
    try {
      out = await outputFile(
        pdf == null ? 'ocr_text' : '${fileBaseName(pdf.path)}_ocr',
        'txt',
      );
      await out.writeAsString(text);
      if (mounted) setState(() => _output = out);
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
    final text = _text;
    final total = _pdf != null ? _pdfPageCount : _images.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Nhận dạng chữ (OCR)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Lấy chữ từ ảnh chụp hoặc PDF bản scan, đọc được tiếng Việt.',
            style: muted,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PickTile(
                  icon: Icons.photo_library_outlined,
                  label: 'Chọn ảnh',
                  picked: _images.isEmpty
                      ? null
                      : '${_images.length} ảnh',
                  onPick: _pickGallery,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.photo_camera_outlined),
                tooltip: 'Chụp ảnh',
                onPressed: _pickCamera,
              ),
            ],
          ),
          if (_images.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _images[i],
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF bản scan',
            picked: _pdf == null ? null : fileBaseName(_pdf!.path),
            onPick: _pickPdf,
            trailing: _pdf == null
                ? null
                : Chip(label: Text('$_pdfPageCount trang')),
          ),
          const SizedBox(height: 16),
          if (_running)
            RunningPane(
              message: _progress,
              onCancel: _cancelRequested ? null : _cancel,
            )
          else
            RunButton(
              label: total == 0
                  ? 'Nhận dạng chữ'
                  : 'Nhận dạng chữ trong $total '
                        '${_pdf != null ? 'trang' : 'ảnh'}',
              onPressed: _run,
              enabled: total > 0,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (text != null) ...[
            if (_notice != null) ...[
              Text(_notice!, style: muted),
              const SizedBox(height: 8),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  text.length > _previewChars
                      ? '${text.substring(0, _previewChars)}…'
                      : text,
                ),
              ),
            ),
            if (text.length > _previewChars) ...[
              const SizedBox(height: 4),
              Text(
                'Đang hiện phần đầu. Bấm "Lưu .txt" để có toàn bộ chữ.',
                style: muted,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Sao chép'),
                    onPressed: _copy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.save),
                    label: const Text('Lưu .txt'),
                    onPressed: _saveTxt,
                  ),
                ),
              ],
            ),
          ],
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
