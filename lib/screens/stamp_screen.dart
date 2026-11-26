import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

/// Insert an image on top of PDF pages (stamp).
class StampScreen extends StatefulWidget {
  const StampScreen({super.key, this.signatureMode = false});

  /// When true, the image picker tile is hidden — the signature flow feeds
  /// bytes via [StampScreenState.setImageBytes].
  final bool signatureMode;

  @override
  State<StampScreen> createState() => StampScreenState();
}

class StampScreenState extends State<StampScreen> {
  File? _input;
  File? _image;
  Uint8List? _imageBytes;

  bool get _hidePicker => widget.signatureMode;
  int _pageCount = 0;
  List<PdfPageInfo> _pageInfos = const [];
  int _targetPage = 0; // -1 = all pages
  double _widthPct = 0.35;
  PdfCorner _corner = PdfCorner.bottomRight;
  double _opacity = 1.0;
  bool _running = false;
  File? _output;
  String? _error;

  static const _corners = <PdfCorner, String>{
    PdfCorner.topLeft: 'Trên trái',
    PdfCorner.topRight: 'Trên phải',
    PdfCorner.bottomLeft: 'Dưới trái',
    PdfCorner.bottomRight: 'Dưới phải',
  };

  Future<void> _pickPdf() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    final f = files.first;
    try {
      final infos = await PdfEngine.instance.pageInfo(f);
      setState(() {
        _input = f;
        _pageInfos = infos;
        _pageCount = infos.length;
        _targetPage = 0;
        _output = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _pickImage() async {
    final files = await pickImages(multiple: false);
    if (files == null || files.isEmpty) return;
    final f = files.first;
    setState(() {
      _image = f;
      _imageBytes = f.readAsBytesSync();
      _output = null;
      _error = null;
    });
  }

  void setImageBytes(Uint8List bytes) => setState(() {
        _imageBytes = bytes;
        _image = null;
      });

  PdfRect _bounds(PdfRect pageBox) {
    // Page box origin is usually (0,0) but be safe with offsets.
    final w = pageBox.width * _widthPct;
    final h = w; // square stamp — keeps it simple and predictable
    final x = switch (_corner) {
      PdfCorner.topLeft || PdfCorner.bottomLeft => pageBox.x + 24,
      PdfCorner.topRight || PdfCorner.bottomRight =>
        pageBox.x + pageBox.width - w - 24,
    };
    final y = switch (_corner) {
      PdfCorner.topLeft || PdfCorner.topRight =>
        pageBox.y + pageBox.height - h - 24,
      PdfCorner.bottomLeft || PdfCorner.bottomRight => pageBox.y + 24,
    };
    return PdfRect(x: x, y: y, width: w, height: h);
  }

  Future<void> run() async {
    final input = _input;
    final bytes = _imageBytes;
    if (input == null || bytes == null || _pageInfos.isEmpty) return;
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final out = await outputFile(
        '${input.path.split('/').last}_stamp',
        'pdf',
      );
      final bounds = _bounds(
        _pageInfos[_targetPage == -1 ? 0 : _targetPage].mediaBox,
      );
      await PdfEngine.instance.addImageStamp(
        input,
        out,
        bytes,
        bounds: bounds,
        pages: _targetPage == -1
            ? const PdfPages.all()
            : PdfPages.single(_targetPage),
        opacity: _opacity,
      );
      setState(() => _output = out);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Widget buildOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _targetPage,
          decoration: const InputDecoration(labelText: 'Trang đặt ảnh'),
          items: [
            const DropdownMenuItem(value: -1, child: Text('Tất cả trang')),
            for (var i = 0; i < _pageCount; i++)
              DropdownMenuItem(value: i, child: Text('Trang ${i + 1}')),
          ],
          onChanged: (v) => setState(() => _targetPage = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PdfCorner>(
          initialValue: _corner,
          decoration: const InputDecoration(labelText: 'Vị trí'),
          items: [
            for (final e in _corners.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _corner = v!),
        ),
        const SizedBox(height: 12),
        Text('Kích thước: ${(_widthPct * 100).round()}% chiều rộng trang'),
        Slider(
          value: _widthPct,
          min: 0.05,
          max: 1.0,
          divisions: 19,
          onChanged: (v) => setState(() => _widthPct = v),
        ),
        Text('Độ mờ: ${(_opacity * 100).round()}%'),
        Slider(
          value: _opacity,
          min: 0.1,
          max: 1.0,
          divisions: 9,
          onChanged: (v) => setState(() => _opacity = v),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chèn ảnh vào PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF',
            picked: _input?.path.split('/').last,
            onPick: _pickPdf,
            trailing: _pageCount > 0 ? Text('$_pageCount trang') : null,
          ),
          const SizedBox(height: 8),
          if (_hidePicker)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const IconTile(Icons.draw_outlined, size: 48),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _imageBytes == null
                            ? 'Vẽ chữ ký ở trên, rồi bấm "Dùng chữ ký này"'
                            : 'Chữ ký đã sẵn sàng',
                      ),
                    ),
                    if (_imageBytes != null)
                      Icon(
                        Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
              ),
            )
          else
            PickTile(
              icon: Icons.image_outlined,
              label: 'Chọn ảnh để chèn',
              picked: _image?.path.split('/').last,
              onPick: _pickImage,
              trailing: _imageBytes != null
                  ? Icon(
                      Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
            ),
          const SizedBox(height: 16),
          if (_pageInfos.isNotEmpty && _imageBytes != null)
            buildOptions(context),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang chèn ảnh…')
          else
            RunButton(
              label: widget.signatureMode ? 'Ký vào PDF' : 'Chèn ảnh',
              enabled: _input != null && _imageBytes != null,
              onPressed: run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
