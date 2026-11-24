import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

class ImagesToPdfScreen extends StatefulWidget {
  const ImagesToPdfScreen({super.key});

  @override
  State<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends State<ImagesToPdfScreen> {
  final List<File> _images = [];
  int _pageSize = 0; // 0 = theo ảnh, 1 = A4, 2 = Letter
  bool _running = false;
  File? _output;
  String? _error;

  Future<void> _add() async {
    final files = await pickImages(multiple: true);
    if (files == null) return;
    setState(() {
      _images.addAll(files);
      _output = null;
      _error = null;
    });
  }

  Future<void> _capture() async {
    final photo = await capturePhoto();
    if (photo == null) return;
    setState(() {
      _images.add(photo);
      _output = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final out = await outputFile('anh_to_pdf', 'pdf');
      final page = switch (_pageSize) {
        1 => const PdfImagePage(
            size: PdfImagePageSize.fixed(PdfPageSize.a4()),
            fit: PdfImageFit.contain,
          ),
        2 => const PdfImagePage(
            size: PdfImagePageSize.fixed(PdfPageSize.letter()),
            fit: PdfImageFit.contain,
          ),
        _ => const PdfImagePage(),
      };
      await PdfEngine.instance.imagesToPdf(_images, out, page: page);
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
      appBar: AppBar(title: const Text('Ảnh → PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.photo_library,
            label: 'Chọn ảnh từ thư viện',
            picked: _images.isEmpty ? null : '${_images.length} ảnh',
            onPick: _add,
          ),
          const SizedBox(height: 8),
          PickTile(
            icon: Icons.camera_alt,
            label: 'Chụp ảnh mới',
            onPick: _capture,
          ),
          const SizedBox(height: 8),
          Text(
            'Thứ tự ảnh = thứ tự trang.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          PickedFilesList(
            files: _images,
            onRemove: (i) => setState(() => _images.removeAt(i)),
          ),
          const SizedBox(height: 8),
          Text('Khổ trang', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final (i, label) in [
                (0, 'Theo ảnh'),
                (1, 'A4'),
                (2, 'Letter'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _pageSize == i,
                  onSelected: (_) => setState(() => _pageSize = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang tạo PDF…')
          else
            RunButton(
              label: 'Tạo PDF',
              enabled: _images.isNotEmpty,
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
