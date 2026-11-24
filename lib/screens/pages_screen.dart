import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// Page editor: thumbnails with rotate/delete + drag-to-reorder.
class PagesScreen extends StatefulWidget {
  const PagesScreen({super.key});

  @override
  State<PagesScreen> createState() => _PagesScreenState();
}

class _PageState {
  _PageState(this.originalIndex, this.rotation, this.deleted, this.thumb);
  final int originalIndex;
  PdfRotation rotation;
  bool deleted;
  Uint8List? thumb;
}

class _PagesScreenState extends State<PagesScreen> {
  File? _input;
  List<_PageState> _pages = [];
  bool _loading = false;
  bool _running = false;
  File? _output;
  String? _error;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    final f = files.first;
    setState(() {
      _input = f;
      _pages = [];
      _output = null;
      _error = null;
      _loading = true;
    });
    try {
      final count = await PdfEngine.instance.info(f).then((i) => i.pageCount);
      if (count > 200) {
        setState(() {
          _loading = false;
          _error = 'File quá lớn ($count trang) — tối đa 200 trang.';
        });
        return;
      }
      final pages = [
        for (var i = 0; i < count; i++)
          _PageState(i, PdfRotation.r0, false, null),
      ];
      setState(() => _pages = pages);
      // Render thumbnails sequentially at low dpi.
      for (final p in pages) {
        try {
          final b = await PdfEngine.instance.pageBitmap(f, p.originalIndex,
              dpi: 50);
          p.thumb = b.bytes;
          if (mounted) setState(() {});
        } catch (_) {}
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  PdfRotation _next(PdfRotation r) => switch (r) {
        PdfRotation.r0 => PdfRotation.r90,
        PdfRotation.r90 => PdfRotation.r180,
        PdfRotation.r180 => PdfRotation.r270,
        PdfRotation.r270 => PdfRotation.r0,
      };

  Future<void> _run() async {
    final input = _input;
    if (input == null) return;
    final kept = _pages.where((p) => !p.deleted).toList();
    if (kept.isEmpty) {
      setState(() => _error = 'Không thể xóa hết tất cả trang.');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final out = await outputFile(
        '${input.path.split('/').last}_edited',
        'pdf',
      );
      await PdfEngine.instance.editPages(
        input,
        out,
        order: kept.map((p) => p.originalIndex).toList(),
        rotations: {for (final p in kept) p.originalIndex: p.rotation},
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
      appBar: AppBar(title: const Text('Sắp xếp trang')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf,
            label: 'Chọn PDF để sửa trang',
            picked: _input?.path.split('/').last,
            onPick: _pick,
          ),
          const SizedBox(height: 8),
          if (_loading) const RunningPane(message: 'Đang đọc trang…'),
          if (_pages.isNotEmpty) ...[
            Text(
              'Giữ và kéo để đổi thứ tự. ${_pages.where((p) => p.deleted).length} trang sẽ bị xóa.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final p = _pages.removeAt(oldIndex);
                  _pages.insert(newIndex, p);
                });
              },
              children: [
                for (final p in _pages)
                  Card(
                    key: ValueKey(p.originalIndex),
                    child: ListTile(
                      leading: SizedBox(
                        width: 48,
                        child: p.thumb == null
                            ? const Icon(Icons.picture_as_pdf)
                            : RotatedBox(
                                quarterTurns: p.rotation ==
                                        PdfRotation.r0
                                    ? 0
                                    : p.rotation == PdfRotation.r90
                                        ? 1
                                        : p.rotation == PdfRotation.r180
                                            ? 2
                                            : 3,
                                child: Image.memory(
                                  p.thumb!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                      ),
                      title: Text(
                        'Trang ${p.originalIndex + 1}'
                        '${p.deleted ? ' (sẽ xóa)' : ''}',
                        style: p.deleted
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Xoay 90°',
                            icon: const Icon(Icons.rotate_right),
                            onPressed: () =>
                                setState(() => p.rotation = _next(p.rotation)),
                          ),
                          IconButton(
                            tooltip: p.deleted ? 'Khôi phục' : 'Xóa trang',
                            icon: Icon(
                              p.deleted
                                  ? Icons.undo
                                  : Icons.delete_outline,
                            ),
                            onPressed: () =>
                                setState(() => p.deleted = !p.deleted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_running)
              const RunningPane(message: 'Đang lưu PDF…')
            else
              RunButton(label: 'Lưu PDF mới', onPressed: _run),
          ],
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
