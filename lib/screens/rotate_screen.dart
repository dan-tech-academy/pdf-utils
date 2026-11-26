import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

/// Turns every page of one or more PDFs the same way.
class RotateScreen extends StatefulWidget {
  const RotateScreen({super.key});

  @override
  State<RotateScreen> createState() => _RotateScreenState();
}

class _RotateScreenState extends State<RotateScreen> {
  /// The choices in display order: turn, label, icon.
  static const _directions = <(PdfRotation, String, IconData)>[
    (PdfRotation.r90, 'Xoay phải', Icons.rotate_right_rounded),
    (PdfRotation.r270, 'Xoay trái', Icons.rotate_left_rounded),
    (PdfRotation.r180, 'Lật ngược', Icons.swap_vert_rounded),
  ];

  final List<File> _inputs = [];
  PdfRotation _rotation = PdfRotation.r90;

  /// First page of the first file as it looks now, for the preview.
  Uint8List? _preview;
  String? _previewPath;

  bool _running = false;

  /// 1-based number of the file being rotated.
  int _current = 0;
  List<File> _outputs = const [];
  String? _outputNote;
  String? _error;

  Future<void> _add() async {
    if (_running) return;
    final files = await pickPdfs(multiple: true);
    if (!mounted || files == null) return;
    final known = {for (final f in _inputs) f.path};
    setState(() {
      _inputs.addAll(files.where((f) => known.add(f.path)));
      _outputs = const [];
      _error = null;
    });
    unawaited(_loadPreview());
  }

  void _remove(int index) {
    setState(() {
      _inputs.removeAt(index);
      _outputs = const [];
      _error = null;
    });
    unawaited(_loadPreview());
  }

  /// Renders the first page of the first file when that file changed.
  Future<void> _loadPreview() async {
    final first = _inputs.isEmpty ? null : _inputs.first;
    if (first?.path == _previewPath) return;
    _previewPath = first?.path;
    setState(() => _preview = null);
    if (first == null) return;
    try {
      final page = await PdfEngine.instance.pageBitmap(first, 0, dpi: 50);
      if (mounted && _previewPath == first.path) {
        setState(() => _preview = page.bytes);
      }
    } catch (_) {
      // A locked or damaged file just gets no preview; rotating it reports
      // the reason.
    }
  }

  Future<void> _run() async {
    final inputs = List<File>.of(_inputs);
    if (inputs.isEmpty || _running) return;
    final rotation = _rotation;
    setState(() {
      _running = true;
      _current = 1;
      _error = null;
      _outputs = const [];
    });
    final outputs = <File>[];
    final failures = <String>[];
    final taken = <String>{};
    // One file failing (say, a locked one) doesn't stop the others.
    for (var i = 0; i < inputs.length; i++) {
      if (!mounted) return;
      setState(() => _current = i + 1);
      final input = inputs[i];
      File? out;
      try {
        out = await _newOutput('${fileBaseName(input.path)}_xoay', taken);
        await PdfEngine.instance.rotatePages(input, out, by: rotation);
        outputs.add(out);
      } catch (e) {
        deleteQuietly(out);
        failures.add(
          inputs.length == 1
              ? friendlyError(e)
              : '${fileBaseName(input.path)}: ${friendlyError(e)}',
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _outputs = outputs;
      _outputNote = 'Đã ${_labelOf(rotation).toLowerCase()} tất cả các trang';
      _error = switch (failures) {
        [] => null,
        [final only] when inputs.length == 1 => only,
        _ =>
          'Không xoay được ${failures.length}/${inputs.length} file:\n'
              '${failures.join('\n')}',
      };
    });
  }

  /// [outputFile] for [base], with `_2`, `_3`… added when the name is taken:
  /// files picked from different folders can share a name, and the
  /// timestamp in the name only counts whole seconds.
  Future<File> _newOutput(String base, Set<String> taken) async {
    final first = await outputFile(base, 'pdf');
    var out = first;
    for (var n = 2; out.existsSync() || !taken.add(out.path); n++) {
      out = File(first.path.replaceFirst(RegExp(r'\.pdf$'), '_$n.pdf'));
    }
    return out;
  }

  static String _labelOf(PdfRotation rotation) =>
      _directions.firstWhere((d) => d.$1 == rotation).$2;

  /// Clockwise quarter turns, as [RotatedBox] counts them.
  static int _quarterTurns(PdfRotation rotation) => switch (rotation) {
    PdfRotation.r0 => 0,
    PdfRotation.r90 => 1,
    PdfRotation.r180 => 2,
    PdfRotation.r270 => 3,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _inputs.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Xoay PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF cần xoay',
            picked: count == 0 ? null : '$count file',
            onPick: _add,
          ),
          PickedFilesList(files: _inputs, onRemove: _running ? null : _remove),
          const SizedBox(height: 16),
          Text('Hướng xoay', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<PdfRotation>(
            showSelectedIcon: false,
            segments: [
              for (final (rotation, label, icon) in _directions)
                ButtonSegment(
                  value: rotation,
                  // The icon sits above the label: beside it, the three
                  // labels would wrap on a narrow phone. The padding keeps
                  // the column inside the segment border, which is inset
                  // 4 px and clips, at large text sizes.
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon),
                        const SizedBox(height: 4),
                        Text(label, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
            ],
            selected: {_rotation},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() => _rotation = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'Tất cả các trang trong file sẽ được xoay.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_preview case final png?) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _PreviewPage(
                    png: png,
                    quarterTurns: 0,
                    caption: 'Trước',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Flexible(
                  child: _PreviewPage(
                    png: png,
                    quarterTurns: _quarterTurns(_rotation),
                    caption: 'Sau',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (_running)
            RunningPane(
              message: count > 1
                  ? 'Đang xoay file $_current/$count…'
                  : 'Đang xoay…',
            )
          else
            RunButton(
              label: count == 0 ? 'Xoay PDF' : 'Xoay $count file',
              enabled: count > 0,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_outputs.length == 1)
            ResultCard(file: _outputs.single, extra: _outputNote)
          else if (_outputs.length > 1)
            ResultFilesCard(files: _outputs),
        ],
      ),
    );
  }
}

/// The first page in a fixed square, turned by [quarterTurns], with a
/// caption below.
class _PreviewPage extends StatelessWidget {
  const _PreviewPage({
    required this.png,
    required this.quarterTurns,
    required this.caption,
  });

  final Uint8List png;
  final int quarterTurns;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 132,
          child: Center(
            child: RotatedBox(
              quarterTurns: quarterTurns,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Image.memory(png, excludeFromSemantics: true),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
