import 'dart:io';

import 'package:doc_scanner_kit/document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// Scan documents to PDF. Primary: ML Kit Document Scanner (Android) /
/// VisionKit (iOS) via doc_scanner_kit. Fallback: camera photo → PDF.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _pages = TextEditingController(text: '4');
  bool _running = false;
  File? _output;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final status = await Permission.camera.request();
      if (status.isDenied) {
        setState(() => _error = 'Chưa cấp quyền camera.');
        return;
      }
      final pageLimit = int.tryParse(_pages.text.trim()) ?? 4;
      final result = await DocumentScanner()
          .getScannedDocumentAsPdf(page: pageLimit);
      if (result == null) {
        setState(() => _error = 'Đã hủy scan.');
        return;
      }
      final file = await _resolveResult(result);
      if (file == null) {
        setState(() => _error = 'Không đọc được kết quả scan.');
        return;
      }
      final out = await outputFile('scan', 'pdf');
      await file.copy(out.path);
      setState(() => _output = out);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Normalizes the plugin result into a readable file.
  Future<File?> _resolveResult(dynamic result) async {
    // Android returns {'pdfUri': 'content://…', 'pageCount': n}
    if (result is Map) {
      final uri = result['pdfUri'] ?? result['Uri'] ?? result['uri'];
      if (uri != null) {
        if (uri.toString().startsWith('content://')) {
          return contentUriToFile(uri.toString());
        }
        final f = File(uri.toString());
        return f.existsSync() ? f : null;
      }
    }
    if (result is String) {
      if (result.startsWith('content://')) return contentUriToFile(result);
      final f = File(result);
      return f.existsSync() ? f : null;
    }
    return null;
  }

  /// Fallback: capture one photo with the camera and wrap it as a PDF.
  Future<void> _cameraFallback() async {
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final status = await Permission.camera.request();
      if (status.isDenied) {
        setState(() => _error = 'Chưa cấp quyền camera.');
        return;
      }
      final photo = await capturePhoto();
      if (photo == null) {
        setState(() => _error = 'Đã hủy chụp ảnh.');
        return;
      }
      final out = await outputFile('scan_camera', 'pdf');
      await PdfEngine.instance.imagesToPdf([photo], out);
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
      appBar: AppBar(title: const Text('Scan → PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const IconTile(Icons.document_scanner_outlined, size: 56),
                  const SizedBox(height: 12),
                  const Text(
                    'Quét tài liệu bằng camera: tự nhận mép, cắt gọn, '
                    'làm sạch ảnh và xuất thẳng ra PDF.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pages,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Số trang tối đa',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang scan…')
          else ...[
            RunButton(label: 'Bắt đầu scan', onPressed: _scan),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _cameraFallback,
                child: const Text('Hoặc chụp ảnh đơn giản (không cắt mép)'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}
