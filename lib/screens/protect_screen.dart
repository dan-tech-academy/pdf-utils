import 'dart:io';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

/// Lock (encrypt) or unlock (decrypt) a PDF.
class ProtectScreen extends StatefulWidget {
  const ProtectScreen({super.key});

  @override
  State<ProtectScreen> createState() => _ProtectScreenState();
}

class _ProtectScreenState extends State<ProtectScreen> {
  File? _input;
  bool _lock = true;
  final _password = TextEditingController();
  bool _running = false;
  File? _output;
  String? _error;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    setState(() {
      _input = files.first;
      _output = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null) return;
    final pw = _password.text;
    if (_lock && pw.isEmpty) {
      setState(() => _error = 'Nhập mật khẩu để khóa file.');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final suffix = _lock ? '_locked' : '_unlocked';
      final out = await outputFile(
        '${input.path.split('/').last}$suffix',
        'pdf',
      );
      if (_lock) {
        await PdfEngine.instance.encrypt(input, out, pw);
      } else {
        await PdfEngine.instance.decrypt(input, out,
            password: pw.isEmpty ? null : pw);
      }
      setState(() => _output = out);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Khóa / Mở khóa PDF')),
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
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Khóa bằng mật khẩu'),
                icon: Icon(Icons.lock_outline),
              ),
              ButtonSegment(
                value: false,
                label: Text('Mở khóa'),
                icon: Icon(Icons.lock_open_outlined),
              ),
            ],
            selected: {_lock},
            onSelectionChanged: (s) => setState(() => _lock = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText:
                  _lock ? 'Mật khẩu mới' : 'Mật khẩu hiện tại (nếu có)',
            ),
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang xử lý…')
          else
            RunButton(
              label: _lock ? 'Khóa file' : 'Mở khóa',
              enabled: _input != null,
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
