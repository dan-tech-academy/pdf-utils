import 'dart:io';

import 'package:flutter/material.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

class MergeScreen extends StatefulWidget {
  const MergeScreen({super.key});

  @override
  State<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends State<MergeScreen> {
  final List<File> _inputs = [];
  bool _running = false;
  File? _output;
  String? _error;

  Future<void> _add() async {
    final files = await pickPdfs(multiple: true);
    if (files == null) return;
    setState(() {
      _inputs.addAll(files);
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
      final out = await outputFile('merged', 'pdf');
      await PdfEngine.instance.merge(_inputs, out);
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
      appBar: AppBar(title: const Text('Ghép PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.library_add_outlined,
            label: 'Chọn các PDF (ít nhất 2)',
            picked: _inputs.isEmpty ? null : '${_inputs.length} file',
            onPick: _add,
          ),
          const SizedBox(height: 8),
          Text(
            'Thứ tự trong danh sách là thứ tự trong file kết quả.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          PickedFilesList(
            files: _inputs,
            onRemove: (i) => setState(() => _inputs.removeAt(i)),
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang ghép…')
          else
            RunButton(
              label: 'Ghép lại',
              enabled: _inputs.length >= 2,
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
