import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

/// A PNG plus the size, in PDF points, it should cover on the page.
class OverlayImage {
  const OverlayImage(this.png, this.width, this.height);

  final Uint8List png;
  final double width;
  final double height;
}

/// A page as a reader sees it: the visible box turned by the page's
/// `/Rotate`. "Display" coordinates are points from the top-left of that
/// view with y pointing down, the same orientation [PdfEngine.pageBitmap]
/// renders, so a widget drawn over a page bitmap maps straight to them.
///
/// The engine stamps images in PDF user space, which a viewer turns by
/// `/Rotate`. To look upright, an overlay must therefore be pre-turned with
/// [uprightForPage] and placed at [toPdf] of its display rectangle.
class PageGeometry {
  PageGeometry(PdfPageInfo info)
    : box = _visibleBox(info),
      quarterTurns = switch (info.rotation) {
        PdfRotation.r0 => 0,
        PdfRotation.r90 => 1,
        PdfRotation.r180 => 2,
        PdfRotation.r270 => 3,
      };

  /// The visible box in PDF user space.
  final PdfRect box;

  /// The crop box clipped to the media box, which is what viewers and the
  /// renderer show; the media box when there is no crop box or it misses
  /// the page.
  static PdfRect _visibleBox(PdfPageInfo info) {
    final media = info.mediaBox;
    final crop = info.cropBox;
    if (crop == null) return media;
    final left = math.max(crop.x, media.x);
    final bottom = math.max(crop.y, media.y);
    final right = math.min(crop.x + crop.width, media.x + media.width);
    final top = math.min(crop.y + crop.height, media.y + media.height);
    if (right <= left || top <= bottom) return media;
    return PdfRect.fromEdges(
      left: left,
      bottom: bottom,
      right: right,
      top: top,
    );
  }

  /// Clockwise quarter turns a viewer applies (`/Rotate` / 90).
  final int quarterTurns;

  /// Displayed width in points.
  double get width => quarterTurns.isOdd ? box.height : box.width;

  /// Displayed height in points.
  double get height => quarterTurns.isOdd ? box.width : box.height;

  /// Maps a rectangle in display points to PDF user space.
  PdfRect toPdf(Rect r) {
    final (x1, y1) = _toUser(r.left, r.top);
    final (x2, y2) = _toUser(r.right, r.bottom);
    return PdfRect.fromEdges(
      left: math.min(x1, x2),
      bottom: math.min(y1, y2),
      right: math.max(x1, x2),
      top: math.max(y1, y2),
    );
  }

  (double, double) _toUser(double dx, double dy) {
    final left = box.x;
    final bottom = box.y;
    final right = box.x + box.width;
    final top = box.y + box.height;
    return switch (quarterTurns) {
      0 => (left + dx, top - dy),
      1 => (left + dy, bottom + dx),
      2 => (right - dx, bottom + dy),
      _ => (right - dy, top - dx),
    };
  }

  /// [png] turned counter-clockwise by the page rotation, so that it reads
  /// upright once a viewer applies `/Rotate`.
  Future<Uint8List> uprightForPage(Uint8List png) async {
    final q = quarterTurns % 4;
    if (q == 0) return png;
    final codec = await ui.instantiateImageCodec(png);
    final src = (await codec.getNextFrame()).image;
    codec.dispose();
    final w = src.width;
    final h = src.height;
    final outW = q.isOdd ? h : w;
    final outH = q.isOdd ? w : h;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(outW / 2, outH / 2)
      ..rotate(-q * math.pi / 2)
      ..drawImage(src, ui.Offset(-w / 2, -h / 2), ui.Paint());
    final picture = recorder.endRecording();
    final out = await picture.toImage(outW, outH);
    picture.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    out.dispose();
    return data!.buffer.asUint8List();
  }
}

/// Renders [text] in the app font (Be Vietnam Pro) to a transparent PNG.
///
/// The engine's built-in PDF fonts cannot draw Vietnamese, so text that a
/// tool writes onto pages goes through this and is stamped as an image.
/// [angleDegrees] turns the text counter-clockwise; the result is the
/// bounding box of the turned text. Sizes are in PDF points.
Future<OverlayImage> renderTextImage(
  String text, {
  required double fontSize,
  required Color color,
  double angleDegrees = 0,
  FontWeight fontWeight = FontWeight.w600,
  double pixelsPerPoint = 4,
}) async {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'BeVietnamPro',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.2,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();
  final w = painter.width;
  final h = painter.height;
  final rad = angleDegrees * math.pi / 180;
  final boxW = (w * math.cos(rad)).abs() + (h * math.sin(rad)).abs();
  final boxH = (w * math.sin(rad)).abs() + (h * math.cos(rad)).abs();
  // Keep big watermarks under ~4k pixels on the long side.
  final scale = math.min(pixelsPerPoint, 4096 / math.max(boxW, boxH));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..translate(boxW / 2, boxH / 2)
    ..rotate(-rad);
  painter.paint(canvas, Offset(-w / 2, -h / 2));
  painter.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    math.max(1, (boxW * scale).ceil()),
    math.max(1, (boxH * scale).ceil()),
  );
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return OverlayImage(data!.buffer.asUint8List(), boxW, boxH);
}
