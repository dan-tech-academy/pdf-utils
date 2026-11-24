import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

/// Extract all text from a PDF; preview + save as .txt.
class TextScreen extends StatefulWidget {
  const TextScreen({super.key});

  @override
  State<TextScreen> createState() => _TextScreenState();
}

class _TextScreenState extends State<TextScreen> {
  File? _input;
  bool _running = false;
  String? _text;
  File? _output;
  String? _error;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    setState(() {
      _input = files.first;
      _text = null;
      _output = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null) return;
    setState(() {
      _running = true;
      _error = null;
      _text = null;
      _output = null;
    });
    try {
      final text = await PdfEngine.instance.extractText(input);
      final out = await outputFile(
        '${input.path.split('/').last}_text',
        'txt',
      );
      await out.writeAsString(text);
      setState(() {
        _text = text;
        _output = out;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trích xuất text')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf,
            label: 'Chọn PDF',
            picked: _input?.path.split('/').last,
            onPick: _pick,
          ),
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
                label: const Text('Copy'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _text!)),
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
