import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  File? _input;
  int _mode = 0; // 0 = mỗi N trang, 1 = từng trang, 2 = theo kích thước MB
  final _every = TextEditingController(text: '1');
  final _mb = TextEditingController(text: '5');
  bool _running = false;
  List<File>? _outputs;
  String? _error;
  int? _pageCount;

  Future<void> _pick() async {
    final files = await pickPdfs();
    if (files == null || files.isEmpty) return;
    final f = files.first;
    int? count;
    try {
      count = await PdfEngine.instance.info(f).then((i) => i.pageCount);
    } catch (_) {}
    setState(() {
      _input = f;
      _pageCount = count;
      _outputs = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null) return;
    setState(() {
      _running = true;
      _error = null;
      _outputs = null;
    });
    try {
      final dir = await outputsDir();
      final base =
          input.path.split('/').last.replaceAll(RegExp(r'\.pdf$'), '');
      final rule = switch (_mode) {
        0 => PdfSplitRule.every(int.parse(_every.text.trim())),
        1 => const PdfSplitRule.every(1),
        _ => PdfSplitRule.maxBytes(
            (double.parse(_mb.text.trim()) * 1024 * 1024).round()),
      };
      final files =
          await PdfEngine.instance.split(input, dir, base, by: rule);
      setState(() => _outputs = files);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tách PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF cần tách',
            picked: _input?.path.split('/').last,
            onPick: _pick,
            trailing: _pageCount == null
                ? null
                : Text('$_pageCount trang'),
          ),
          const SizedBox(height: 16),
          Text('Cách tách', style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<int>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            child: Column(
              children: [
                RadioListTile<int>(
                  dense: true,
                  title: const Text('Mỗi N trang một file'),
                  value: 0,
                ),
                RadioListTile<int>(
                  dense: true,
                  title: const Text('Mỗi trang một file'),
                  value: 1,
                ),
                RadioListTile<int>(
                  dense: true,
                  title: const Text('Không quá N MB mỗi file'),
                  value: 2,
                ),
              ],
            ),
          ),
          if (_mode == 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _every,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Số trang mỗi file'),
              ),
            ),
          if (_mode == 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _mb,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Kích thước tối đa (MB)'),
              ),
            ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang tách…')
          else
            RunButton(
              label: 'Tách',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_outputs != null) ResultFilesCard(files: _outputs!),
        ],
      ),
    );
  }
}
