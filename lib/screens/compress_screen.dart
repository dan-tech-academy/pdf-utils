import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../files.dart';
import '../widgets.dart';

class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key});

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  File? _input;
  PdfImagePolicy _policy = PdfImagePolicy.ebook;
  bool _running = false;
  File? _output;
  String? _error;

  static const _policies = <(String, String, PdfImagePolicy)>[
    (
      'Nhẹ nhất',
      'Màn hình — file nhỏ nhất, chất lượng đủ đọc',
      PdfImagePolicy.screen,
    ),
    (
      'Cân bằng',
      'Ebook — nhỏ mà vẫn rõ',
      PdfImagePolicy.ebook,
    ),
    (
      'Chất lượng cao',
      'In ấn — giữ độ nét cao',
      PdfImagePolicy.print,
    ),
    (
      'Không mất chất lượng',
      'Chỉ đóng gói lại, không giảm ảnh',
      PdfImagePolicy.lossless,
    ),
  ];

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
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    try {
      final out = await outputFile(
        '${input.path.split('/').last}_nen',
        'pdf',
      );
      await PdfEngine.instance.compress(input, out, _policy);
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
      appBar: AppBar(title: const Text('Nén PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF cần nén',
            picked: _input?.path.split('/').last,
            onPick: _pick,
          ),
          const SizedBox(height: 16),
          Text('Mức nén', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          RadioGroup<PdfImagePolicy>(
            groupValue: _policy,
            onChanged: (v) => setState(() => _policy = v!),
            child: Column(
              children: [
                for (final (label, hint, policy) in _policies)
                  RadioListTile<PdfImagePolicy>(
                    dense: true,
                    title: Text(label),
                    subtitle: Text(hint),
                    value: policy,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_running)
            const RunningPane(message: 'Đang nén…')
          else
            RunButton(
              label: 'Nén ngay',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null && _input != null)
            ResultCard(
              file: _output!,
              extra:
                  '${formatBytes(_input!.lengthSync())} → ${formatBytes(_output!.lengthSync())}',
            ),
        ],
      ),
    );
  }
}
