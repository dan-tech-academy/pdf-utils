import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../files.dart';
import 'stamp_screen.dart';

/// Draw signatures, keep a library of saved ones, and stamp a chosen
/// signature onto the PDF.
class SignScreen extends StatefulWidget {
  const SignScreen({super.key});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  final List<List<Offset>> _strokes = [];
  final _boundary = GlobalKey();
  final _stampState = GlobalKey<StampScreenState>();
  List<File> _saved = const [];
  File? _selected;

  @override
  void initState() {
    super.initState();
    _reloadSaved();
  }

  Future<void> _reloadSaved() async {
    final files = await listSignatures();
    if (mounted) setState(() => _saved = files);
  }

  void _select(File f) {
    _stampState.currentState?.setImageBytes(f.readAsBytesSync());
    setState(() => _selected = f);
  }

  Future<void> _delete(File f) async {
    await f.delete();
    if (_selected == f) setState(() => _selected = null);
    await _reloadSaved();
  }

  /// Rasterize the drawn strokes, save as a new signature and select it.
  Future<void> _saveAndUse() async {
    if (_strokes.isEmpty) return;
    final boundary = _boundary.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    final dir = await signaturesDir();
    final name =
        'sig_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png';
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(data.buffer.asUint8List());
    await _reloadSaved();
    setState(() => _strokes.clear());
    _select(f);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ký tên')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_saved.isNotEmpty) ...[
                  Text('Chữ ký đã lưu', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _saved.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final f = _saved[i];
                        final selected = f == _selected;
                        return GestureDetector(
                          onTap: () => _select(f),
                          child: Container(
                            width: 150,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                width: selected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Image.file(f, fit: BoxFit.contain),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: 'Xóa chữ ký',
                                    onPressed: () => _delete(f),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  _saved.isEmpty
                      ? 'Vẽ chữ ký của bạn bên dưới'
                      : 'Vẽ chữ ký mới',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                RepaintBoundary(
                  key: _boundary,
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GestureDetector(
                        onPanStart: (d) => setState(() {
                          _strokes.add([d.localPosition]);
                        }),
                        onPanUpdate: (d) => setState(() {
                          _strokes.last.add(d.localPosition);
                        }),
                        child: CustomPaint(
                          painter: _SignaturePainter(_strokes),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text('Xóa'),
                      onPressed: () => setState(() => _strokes.clear()),
                    ),
                    const SizedBox(width: 8),
                    // Lets the label wrap instead of overflowing at large
                    // text sizes on narrow phones.
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton.tonal(
                          onPressed: _strokes.isEmpty ? null : _saveAndUse,
                          child: const Text(
                            'Lưu & dùng chữ ký',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: _SignatureStampBody(key: _stampState)),
        ],
      ),
    );
  }
}

/// Reuses the stamp screen body (pick PDF + options + run) without the
/// image picker.
class _SignatureStampBody extends StampScreen {
  const _SignatureStampBody({super.key}) : super(signatureMode: true);
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i + 1 < stroke.length; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
