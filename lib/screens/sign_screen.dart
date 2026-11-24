import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'stamp_screen.dart';

/// Draw a signature and stamp it onto the PDF.
class SignScreen extends StatefulWidget {
  const SignScreen({super.key});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  final List<List<Offset>> _strokes = [];
  final _boundary = GlobalKey();
  final _stampState = GlobalKey<StampScreenState>();
  bool _hasPng = false;

  Future<void> _rasterize() async {
    if (_strokes.isEmpty) return;
    final boundary = _boundary.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data != null) {
      _stampState.currentState?.setImageBytes(data.buffer.asUint8List());
      setState(() => _hasPng = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ký tên')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Vẽ chữ ký của bạn bên dưới',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                RepaintBoundary(
                  key: _boundary,
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
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
                      onPressed: () => setState(() {
                        _strokes.clear();
                        _hasPng = false;
                      }),
                    ),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: _strokes.isEmpty ? null : _rasterize,
                      child: Text(
                        _hasPng ? 'Đã chọn ✓' : 'Dùng chữ ký này',
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
