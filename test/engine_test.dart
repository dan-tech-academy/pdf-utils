import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_utils/engine.dart';
import 'package:pdf_utils/page_overlay.dart';

final _engine = PdfEngine.instance;

/// A 3-page PDF whose pages read "Page one", "Page two", "Page three".
Future<File> _threePages(Directory dir) async {
  final f = File('${dir.path}/src.pdf');
  await Pdf().buildTo(await FileSink.open(f), (b) async {
    for (final word in ['one', 'two', 'three']) {
      final page = await b.addPage();
      await page.paragraph('Page $word');
    }
  }, deflate: false);
  return f;
}

Uint8List _png(int w, int h, img.Color Function(int x, int y) color) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixel(x, y, color(x, y));
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('engine_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('keepPages keeps the chosen pages in order', () async {
    final src = await _threePages(dir);
    final out = File('${dir.path}/kept.pdf');
    await _engine.keepPages(src, out, [0, 2]);
    final texts = await _engine.pageTexts(out);
    expect(texts, hasLength(2));
    expect(texts[0], contains('Page one'));
    expect(texts[1], contains('Page three'));
  });

  test('repair rebuilds a file with a broken xref offset', () async {
    final src = await _threePages(dir);
    final text = latin1.decode(src.readAsBytesSync());
    final cut = text.lastIndexOf('startxref');
    final broken = File('${dir.path}/broken.pdf')
      ..writeAsBytesSync(
        latin1.encode('${text.substring(0, cut)}startxref\n999999\n%%EOF\n'),
      );
    final out = File('${dir.path}/fixed.pdf');
    await _engine.repair(broken, out);
    expect((await _engine.pageInfo(out)).length, 3);
  });

  test('convertToPdfA produces a compliant file', () async {
    final src = await _threePages(dir);
    final report = await _engine.convertToPdfA(src, File('${dir.path}/a.pdf'));
    expect(report.isCompliant, isTrue);
  });

  test('extractImages writes JPEGs as JPEG and others as PNG', () async {
    // The engine skips images under 8 px on either side.
    final red = _png(40, 30, (_, _) => img.ColorRgb8(220, 20, 20));
    final jpg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 40, height: 30)),
    );
    final pdf = File('${dir.path}/images.pdf');
    await Pdf().imagesToPdf([
      MemorySource(red),
      MemorySource(jpg),
    ], await FileSink.open(pdf));
    final files = await _engine.extractImages(pdf, dir, 'x');
    expect(files.map((f) => f.path.split('.').last), ['png', 'jpg']);
    expect(files[0].readAsBytesSync().sublist(1, 4), utf8.encode('PNG'));
    expect(files[1].readAsBytesSync().sublist(0, 2), [0xFF, 0xD8]);
  });

  test(
    'an overlay lands upright where it was drawn on a rotated page',
    () async {
      final src = await _threePages(dir);
      final rotated = File('${dir.path}/rotated.pdf');
      await _engine.rotatePages(
        src,
        rotated,
        by: PdfRotation.r90,
        pages: const PdfPages.single(0),
      );
      final geometry = PageGeometry((await _engine.pageInfo(rotated)).first);
      expect(geometry.width, greaterThan(geometry.height));

      // Left half red, right half blue, as the reader should see it.
      final overlay = _png(
        40,
        20,
        (x, _) => x < 20 ? img.ColorRgb8(255, 0, 0) : img.ColorRgb8(0, 0, 255),
      );
      const drawn = Rect.fromLTWH(100, 50, 200, 100);
      final out = File('${dir.path}/stamped.pdf');
      await _engine.addImageStamps(rotated, out, [
        (
          png: await geometry.uprightForPage(overlay),
          bounds: geometry.toPdf(drawn),
          pages: [0],
          opacity: 1.0,
        ),
      ]);

      // 72 dpi: one bitmap pixel per point.
      final bitmap = await _engine.pageBitmap(out, 0, dpi: 72);
      final shown = img.decodePng(bitmap.bytes)!;
      expect(shown.width, closeTo(geometry.width, 1));
      img.Pixel at(double x, double y) => shown.getPixel(x.round(), y.round());
      expect(at(150, 100).r, greaterThan(200)); // left part: red
      expect(at(150, 100).b, lessThan(60));
      expect(at(250, 100).b, greaterThan(200)); // right part: blue
      expect(at(250, 100).r, lessThan(60));
      expect(at(400, 300).r, greaterThan(200)); // outside: white page
      expect(at(400, 300).b, greaterThan(200));
    },
  );

  test('a crop box past the media box is clipped like the renderer', () async {
    final src = await _threePages(dir);
    final media = (await _engine.pageInfo(src)).first.mediaBox;
    final cropped = File('${dir.path}/cropped.pdf');
    await Pdf().rewrite(
      PdfFile(src),
      await FileSink.open(cropped),
      (e) => e.setCropBox(
        const PdfRect(x: -50, y: -50, width: 800, height: 1000),
        pages: const PdfPages.single(0),
      ),
    );
    final geometry = PageGeometry((await _engine.pageInfo(cropped)).first);
    expect(geometry.width, closeTo(media.width, 0.5));
    expect(geometry.height, closeTo(media.height, 0.5));

    final out = File('${dir.path}/stamped.pdf');
    await _engine.addImageStamps(cropped, out, [
      (
        png: _png(10, 10, (_, _) => img.ColorRgb8(255, 0, 0)),
        bounds: geometry.toPdf(const Rect.fromLTWH(20, 30, 40, 40)),
        pages: [0],
        opacity: 1.0,
      ),
    ]);
    final shown = img.decodePng(
      (await _engine.pageBitmap(out, 0, dpi: 72)).bytes,
    )!;
    expect(shown.getPixel(40, 50).r, greaterThan(200));
    expect(shown.getPixel(40, 50).b, lessThan(60));
  });

  test('renderTextImage sizes turned text by its bounding box', () async {
    final flat = await renderTextImage(
      'BẢN SAO',
      fontSize: 40,
      color: const Color(0xFF000000),
    );
    final upright = await renderTextImage(
      'BẢN SAO',
      fontSize: 40,
      color: const Color(0xFF000000),
      angleDegrees: 90,
    );
    expect(flat.width, greaterThan(flat.height));
    expect(upright.height, closeTo(flat.width, 0.5));
    expect(img.decodePng(flat.png), isNotNull);
  });
}
