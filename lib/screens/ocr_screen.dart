import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../files.dart';
import '../widgets.dart';

/// OCR: recognizes text in picked images (or photos) with ML Kit and shows
/// the result for copy / save as .txt. Latin script — covers Vietnamese.
class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  List<File> _images = const [];
  bool _running = false;
  String? _text;
  File? _output;
  String? _error;

  Future<void> _pickGallery() async {
    final files = await pickImages();
    if (files == null) return;
    setState(() {
      _images = files;
      _text = null;
      _output = null;
      _error = null;
    });
  }

  Future<void> _pickCamera() async {
    final file = await capturePhoto();
    if (file == null) return;
    setState(() {
      _images = [file];
      _text = null;
      _output = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    if (_images.isEmpty) return;
    setState(() {
      _running = true;
      _error = null;
      _text = null;
      _output = null;
    });
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final buffer = StringBuffer();
      for (final f in _images) {
        final input = InputImage.fromFile(f);
        final result = await recognizer.processImage(input);
        if (result.text.trim().isNotEmpty) {
          buffer.writeln(result.text);
          buffer.writeln();
        }
      }
      await recognizer.close();
      final text = buffer.toString().trim();
      if (text.isEmpty) {
        setState(() => _error = 'Không nhận diện được chữ nào trong ảnh.');
      } else {
        setState(() => _text = text);
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  Future<void> _saveTxt() async {
    final text = _text;
    if (text == null) return;
    final out = await outputFile('ocr_text', 'txt');
    await out.writeAsString(text);
    setState(() => _output = out);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR ảnh → text')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          RunButton(
            label: 'Nhận diện text',
            onPressed: _run,
            enabled: !_running && _images.isNotEmpty,
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang nhận diện chữ trong ảnh…'),
          if (_error != null) ErrorBanner(message: _error!),
          if (_text != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(_text!),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: _text!),
                    ),
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
