import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';

import 'errors.dart';
import 'files.dart';
import 'widgets.dart';

/// Screen that first asks the user to pick a PDF, then opens the viewer.
class ViewerPickScreen extends StatefulWidget {
  const ViewerPickScreen({super.key});

  @override
  State<ViewerPickScreen> createState() => _ViewerPickScreenState();
}

class _ViewerPickScreenState extends State<ViewerPickScreen> {
  File? _file;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    setState(() => _file = files.first);
  }

  @override
  Widget build(BuildContext context) {
    if (_file != null) return ViewerScreen(file: _file!);
    return Scaffold(
      appBar: AppBar(title: const Text('Xem PDF')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn file PDF để xem',
            picked: _file?.path.split('/').last,
            onPick: _pick,
          ),
        ),
      ),
    );
  }
}

/// In-app PDF viewer (native PDF renderer via flutter_pdfview).
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.file});
  final File file;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  int _pages = 0;
  int _page = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final name = fileBaseName(widget.file.path);
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Center(
            child: Text('${_page + 1}/$_pages'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Chia sẻ',
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(widget.file.path)]),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorBanner(message: _error!),
              ),
            )
          : PDFView(
              filePath: widget.file.path,
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: true,
              pageFling: true,
              fitPolicy: FitPolicy.BOTH,
              onError: (e) => setState(() => _error = friendlyError(e)),
              onRender: (pages) => setState(() => _pages = pages ?? 0),
              onPageChanged: (page, total) => setState(() {
                _page = page ?? 0;
                _pages = total ?? 0;
              }),
            ),
    );
  }
}
