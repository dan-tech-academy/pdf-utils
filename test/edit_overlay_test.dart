import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_utils/engine.dart';
import 'package:pdf_utils/page_overlay.dart';
import 'package:pdf_utils/screens/edit_screen.dart';
import 'package:pdf_utils/theme.dart';

const _black = Color(0xFF000000);
const _red = Color(0xFFD32F2F);

/// A PDF whose pages read "Page one", "Page two", "Page three", "Page 4"…
Future<void> _writePdf(File file, int pages) async {
  const words = ['one', 'two', 'three'];
  // The library never closes a sink it is handed.
  final sink = await FileSink.open(file);
  try {
    await Pdf().buildTo(sink, (b) async {
      for (var i = 0; i < pages; i++) {
        final page = await b.addPage();
        await page.paragraph('Page ${i < words.length ? words[i] : i + 1}');
      }
    }, deflate: false);
  } finally {
    await sink.close();
  }
}

/// Answers the file picker with [file], as if the user had chosen it.
class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.file);

  final File file;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _PickedFile(file);
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.file);

  final File file;

  @override
  String get name => file.uri.pathSegments.last;

  @override
  Uri get uri => file.uri;

  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => file.lengthSync();

  @override
  Future<int?> length() => file.length();

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}

/// Lets real engine work (page render, image decode) finish between frames
/// until [finder] finds something.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsWidgets);
}

bool _enabled(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    )
    .enabled;

/// Pixels with visible ink inside [points] of an overlay drawn at 3 px/pt.
int _inked(img.Image image, Rect points) {
  var count = 0;
  for (var y = (points.top * 3).round(); y < (points.bottom * 3).round(); y++) {
    for (
      var x = (points.left * 3).round();
      x < (points.right * 3).round();
      x++
    ) {
      if (image.getPixel(x, y).a > 128) count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('edit_overlay_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('marks render at 3 px per point on a transparent overlay', () async {
    final png = await renderPageMarksPng(const [
      HighlightMark(Rect.fromLTWH(10, 10, 50, 20)),
      FrameMark(rect: Rect.fromLTWH(100, 40, 60, 40), color: _red),
      StrokeMark(points: [Offset(20, 90), Offset(80, 90)], color: _black),
      StrokeMark(points: [Offset(180, 20)], color: _black),
      TextMark(
        text: 'Ab',
        topLeft: Offset(10, 50),
        fontSize: 20,
        color: _black,
        maxWidth: 200,
      ),
    ], const Rect.fromLTWH(0, 0, 200, 100));
    final image = img.decodePng(png)!;
    expect((image.width, image.height), (600, 300));
    img.Pixel at(double x, double y) =>
        image.getPixel((x * 3).round(), (y * 3).round());

    final highlight = at(30, 20);
    expect(highlight.a, closeTo(102, 3)); // see-through…
    expect(highlight.r, greaterThan(240)); // …yellow
    expect(highlight.b, lessThan(30));
    expect(at(100, 60).a, 255); // frame edge, in red
    expect(at(100, 60).r, greaterThan(180));
    expect(at(100, 60).g, lessThan(90));
    expect(at(130, 60).a, 0); // inside the frame stays clear
    expect(at(50, 90).a, 255); // pen stroke
    expect(at(180, 20).a, 255); // a tap with the pen leaves a dot
    expect(_inked(image, const Rect.fromLTWH(10, 50, 40, 25)), greaterThan(50));
    expect(_inked(image, const Rect.fromLTWH(60, 45, 30, 35)), 0);
    expect(at(150, 10).a, 0); // untouched
  });

  test('an overlay of part of the page keeps marks where they were', () async {
    const area = Rect.fromLTWH(100, 40, 60, 40);
    final png = await renderPageMarksPng(const [
      FrameMark(rect: Rect.fromLTWH(110, 50, 40, 20), color: _red),
    ], area);
    final image = img.decodePng(png)!;
    expect((image.width, image.height), (180, 120));
    img.Pixel at(double x, double y) => image.getPixel(
      ((x - area.left) * 3).round(),
      ((y - area.top) * 3).round(),
    );
    expect(at(110, 60).a, 255); // the frame's left edge
    expect(at(150, 60).a, 255); // and its right edge
    expect(at(130, 50).a, 255); // and its top
    expect(at(130, 60).a, 0); // inside the frame stays clear
    expect(at(104, 44).a, 0); // the room around it too
  });

  test('the overlay area holds the marks with a margin, cut to the page', () {
    const page = Size(300, 400);
    expect(marksArea(const [], page), Rect.zero);

    final area = marksArea(const [
      HighlightMark(Rect.fromLTWH(50, 60, 40, 20)),
      FrameMark(rect: Rect.fromLTWH(100, 200, 50, 30), color: _red, width: 2),
    ], page);
    // Both marks, the frame's line and a little room for smooth edges.
    expect(area.left, inInclusiveRange(44, 50));
    expect(area.top, inInclusiveRange(54, 60));
    expect(area.right, inInclusiveRange(151, 157));
    expect(area.bottom, inInclusiveRange(231, 237));

    // A stroke that runs off the page stops at its edge.
    final edge = marksArea(const [
      StrokeMark(points: [Offset(280, 380), Offset(340, 450)], color: _black),
    ], page);
    expect(edge.right, page.width);
    expect(edge.bottom, page.height);
    expect(edge.left, inInclusiveRange(270, 279));

    // Text keeps its whole line, accents above capitals included.
    const text = TextMark(
      text: 'Ổn',
      topLeft: Offset(20, 300),
      fontSize: 18,
      color: _black,
      maxWidth: 300,
    );
    final textArea = marksArea(const [text], page);
    expect(textArea.top, lessThan(300));
    expect(textArea.left, lessThan(20));
    expect(textArea.bottom, greaterThan(300 + 18));
  });

  test(
    'saved edits land where they were drawn, also on a rotated page',
    () async {
      final src = File('${dir.path}/src.pdf');
      await _writePdf(src, 3);
      final rotated = File('${dir.path}/rotated.pdf');
      await PdfEngine.instance.rotatePages(
        src,
        rotated,
        by: PdfRotation.r90,
        pages: const PdfPages.single(1),
      );
      final pages = await PdfEngine.instance.pageInfo(rotated);
      final turned = PageGeometry(pages[1]);
      expect(turned.width, greaterThan(turned.height));

      // Off-centre on both axes, so a mirrored or flipped overlay would miss.
      const drawn = Rect.fromLTWH(60, 220, 80, 40);
      final stamps = await buildEditStamps(pages, {
        0: const [HighlightMark(drawn)],
        1: const [HighlightMark(drawn)],
        2: const [],
      });
      expect(
        [for (final s in stamps) s.pages],
        [
          [0],
          [1],
        ],
      );
      // Each stamp covers the highlight and a little room, not the whole
      // page: a page-sized stamp would sit over its links and text.
      for (final s in stamps) {
        final g = PageGeometry(pages[s.pages.single]);
        final mark = g.toPdf(drawn);
        final b = s.bounds;
        final what = 'page ${s.pages.single + 1}';
        // The room on each side, in points.
        expect(
          [
            mark.left - b.left,
            b.right - mark.right,
            mark.bottom - b.bottom,
            b.top - mark.top,
          ],
          everyElement(inInclusiveRange(0, 4)),
          reason: what,
        );
        expect(
          b.width * b.height,
          lessThan(g.width * g.height / 20),
          reason: what,
        );
        // The overlay image is turned with the page, so it fills the stamp
        // at 3 px per point without stretching.
        final overlay = img.decodePng(s.png)!;
        expect(overlay.width, closeTo(b.width * 3, 2), reason: what);
        expect(overlay.height, closeTo(b.height * 3, 2), reason: what);
      }

      final out = File('${dir.path}/edited.pdf');
      await PdfEngine.instance.addImageStamps(rotated, out, stamps);
      bool yellow(img.Pixel p) => p.r > 230 && p.g > 200 && p.b < 200;
      bool white(img.Pixel p) => p.r > 240 && p.g > 240 && p.b > 240;
      final c = drawn.center;
      for (final i in [0, 1, 2]) {
        final g = PageGeometry(pages[i]);
        // 72 dpi: one bitmap pixel per point.
        final bitmap = await PdfEngine.instance.pageBitmap(out, i, dpi: 72);
        final shown = img.decodePng(bitmap.bytes)!;
        expect(shown.width, closeTo(g.width, 1));
        img.Pixel at(double x, double y) =>
            shown.getPixel(x.round(), y.round());
        final page = 'page ${i + 1}';
        expect(yellow(at(c.dx, c.dy)), i < 2, reason: '$page: highlight');
        expect(
          white(at(g.width - c.dx, c.dy)),
          isTrue,
          reason: '$page: mirror',
        );
        expect(white(at(c.dx, g.height - c.dy)), isTrue, reason: '$page: flip');
        // The transparent rest of the overlay must not hide the page.
        expect(
          white(at(g.width - 20, g.height - 20)),
          isTrue,
          reason: '$page: paper',
        );
      }
    },
  );

  test('text tapped near the right edge moves left to stay on the page', () {
    const page = Size(300, 400);
    final edge = TextMark.place(
      'Xin chào',
      const Offset(290, 200),
      fontSize: 13,
      color: _black,
      page: page,
    );
    expect(edge.topLeft.dx, inInclusiveRange(0, 289));
    expect(edge.topLeft.dy, lessThan(200)); // centred on the tapped line
    expect(edge.maxWidth, page.width);

    final middle = TextMark.place(
      'Xin chào',
      const Offset(40, 200),
      fontSize: 13,
      color: _black,
      page: page,
    );
    expect(middle.topLeft.dx, 40);
  });

  testWidgets('edits stay with their page; pen, undo, frame and text work', (
    tester,
  ) async {
    // A small phone. The test font is wider than Be Vietnam Pro, so this
    // also stands in for large text: any overflow fails the test.
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pdf = File('${dir.path}/two.pdf');
    await tester.runAsync(() => _writePdf(pdf, 2));
    FilePickerPlatform.instance = _FakePicker(pdf);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const EditScreen()),
    );
    expect(find.text('Chỉnh sửa PDF'), findsOneWidget);
    await tester.tap(find.text('Chọn PDF cần sửa'));
    await _waitFor(tester, find.byType(RawImage));
    expect(find.text('Trang 1/2'), findsOneWidget);
    expect(_enabled(tester, 'Lưu PDF'), isFalse);
    final page = tester.getRect(find.byType(RawImage));

    await tester.tap(find.text('Vẽ'));
    await tester.pump();
    await tester.dragFrom(page.center, const Offset(60, 40));
    await tester.pump();
    expect(_enabled(tester, 'Lưu PDF'), isTrue);
    await tester.tap(find.text('Hoàn tác'));
    await tester.pump();
    expect(_enabled(tester, 'Lưu PDF'), isFalse);
    expect(_enabled(tester, 'Hoàn tác'), isFalse);

    await tester.tap(find.text('Khung'));
    await tester.pump();
    await tester.dragFrom(
      page.topLeft + const Offset(20, 20),
      const Offset(80, 50),
    );
    await tester.pump();
    expect(_enabled(tester, 'Lưu PDF'), isTrue);

    await tester.tap(find.text('Chữ'));
    await tester.pump();
    await tester.tapAt(page.center);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Thêm chữ'), findsOneWidget);
    expect(_enabled(tester, 'Thêm'), isFalse);
    await tester.enterText(find.byType(TextField), 'Xin chào');
    await tester.pump();
    await tester.tap(find.text('Thêm'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Thêm chữ'), findsNothing);

    // Page 2 starts clean; page 1 keeps its frame and text.
    await tester.tap(find.byTooltip('Trang sau'));
    await tester.pump();
    expect(find.text('Trang 2/2'), findsOneWidget);
    await _waitFor(tester, find.byType(RawImage));
    expect(_enabled(tester, 'Hoàn tác'), isFalse);
    expect(_enabled(tester, 'Lưu PDF'), isTrue);
    await tester.tap(find.byTooltip('Trang trước'));
    await tester.pump();
    await _waitFor(tester, find.byType(RawImage));
    expect(_enabled(tester, 'Hoàn tác'), isTrue);

    // "Trang 1/2" opens the list of pages, which shows the edited ones.
    await tester.tap(find.text('Trang 1/2'));
    await tester.pump(); // the sheet starts sliding up
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Trang 1 · đã sửa'), findsOneWidget);
    await tester.tap(find.text('Trang 2'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Trang 2/2'), findsOneWidget);
    await _waitFor(tester, find.byType(RawImage));
    expect(find.text('Trang 1 · đã sửa'), findsNothing);
    await tester.tap(find.byTooltip('Trang trước'));
    await tester.pump();
    await _waitFor(tester, find.byType(RawImage));
    expect(find.text('Trang 1/2'), findsOneWidget);

    // Leaving with unsaved edits asks first.
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bỏ chỉnh sửa chưa lưu?'), findsOneWidget);
    await tester.tap(find.text('Ở lại'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bỏ chỉnh sửa chưa lưu?'), findsNothing);
    expect(find.byType(EditScreen), findsOneWidget);

    // Page 1 holds the frame and then the text; clearing is undoable too.
    await tester.tap(find.byTooltip('Xóa hết trang này'));
    await tester.pump();
    expect(_enabled(tester, 'Lưu PDF'), isFalse);
    await tester.tap(find.text('Hoàn tác')); // brings both back
    await tester.pump();
    await tester.tap(find.text('Hoàn tác')); // takes the text away
    await tester.pump();
    expect(_enabled(tester, 'Lưu PDF'), isTrue); // the frame is left
    await tester.tap(find.text('Hoàn tác'));
    await tester.pump();
    expect(_enabled(tester, 'Lưu PDF'), isFalse);
    expect(_enabled(tester, 'Hoàn tác'), isFalse);
  });

  testWidgets('the editor fits a small phone at 200 % text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pdf = File('${dir.path}/two.pdf');
    await tester.runAsync(() => _writePdf(pdf, 2));
    FilePickerPlatform.instance = _FakePicker(pdf);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const EditScreen(),
      ),
    );
    await tester.tap(find.text('Chọn PDF cần sửa'));
    await _waitFor(tester, find.byType(RawImage));
    // Every tool's hint and state; any overflow fails the test.
    for (final tool in ['Vẽ', 'Khung', 'Tô sáng', 'Chữ']) {
      await tester.tap(find.text(tool));
      await tester.pump();
    }
    // The page keeps a usable share of the screen.
    expect(tester.getSize(find.byType(RawImage)).height, greaterThan(250));
  });

  testWidgets('the page list is built lazily and opens at the current page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pdf = File('${dir.path}/long.pdf');
    await tester.runAsync(() => _writePdf(pdf, 40));
    FilePickerPlatform.instance = _FakePicker(pdf);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const EditScreen()),
    );
    await tester.tap(find.text('Chọn PDF cần sửa'));
    await _waitFor(tester, find.byType(RawImage));

    Future<void> openList(String label) async {
      await tester.tap(find.text(label));
      await tester.pump(); // the sheet starts sliding up
      await tester.pump(const Duration(milliseconds: 500));
    }

    await openList('Trang 1/40');
    expect(find.text('Trang 1').hitTestable(), findsOneWidget);
    expect(find.text('Trang 40'), findsNothing); // not built yet
    await tester.scrollUntilVisible(
      find.text('Trang 30'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(find.text('Trang 30'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Trang 30/40'), findsOneWidget);
    await _waitFor(tester, find.byType(RawImage));

    // Opened again, the list shows page 30 without scrolling.
    await openList('Trang 30/40');
    expect(find.text('Trang 30').hitTestable(), findsOneWidget);
    expect(find.text('Trang 1'), findsNothing);
  });

  testWidgets('back while saving waits instead of offering to drop edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pdf = File('${dir.path}/two.pdf');
    await tester.runAsync(() => _writePdf(pdf, 2));
    FilePickerPlatform.instance = _FakePicker(pdf);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const EditScreen()),
    );
    await tester.tap(find.text('Chọn PDF cần sửa'));
    await _waitFor(tester, find.byType(RawImage));
    final page = tester.getRect(find.byType(RawImage));
    await tester.tap(find.text('Khung'));
    await tester.pump();
    await tester.dragFrom(
      page.topLeft + const Offset(20, 20),
      const Offset(80, 50),
    );
    await tester.pump();

    await tester.tap(find.text('Lưu PDF'));
    await tester.pump();
    expect(find.text('Đang lưu PDF…'), findsOneWidget);
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bỏ chỉnh sửa chưa lưu?'), findsNothing);
    expect(
      find.text('Đang lưu PDF, vui lòng chờ trong giây lát.'),
      findsOneWidget,
    );
    expect(find.byType(EditScreen), findsOneWidget);

    // Let the save finish. It fails here, as tests have no app folder for
    // the output, and the edits stay for another try.
    final saving = find.text('Đang lưu PDF…');
    for (var i = 0; i < 100 && saving.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(saving, findsNothing);
    expect(_enabled(tester, 'Lưu PDF'), isTrue);
  });
}
