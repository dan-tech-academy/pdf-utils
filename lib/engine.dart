import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';

/// Shared wrapper around the pdf_manipulator engine. `PdfDocument` and
/// `PdfEditor` are not part of the package's public exports, so every op is
/// expressed here as a concrete method — closure parameter types stay
/// inferred inside this file.
class PdfEngine {
  PdfEngine._();
  static final PdfEngine instance = PdfEngine._();

  final Pdf _pdf = Pdf();

  Future<PdfDocumentInfo> info(File file) => _pdf.info(PdfFile(file));

  /// Merge PDFs in order into [output].
  Future<void> merge(List<File> inputs, File output) async {
    final sink = await FileSink.open(output);
    await _pdf.merge(inputs.map((f) => PdfFile(f)).toList(), sink);
  }

  /// Compress with the given image policy; never grows the file.
  Future<void> compress(File input, File output, PdfImagePolicy policy) async {
    final sink = await FileSink.open(output);
    await _pdf.compress(PdfFile(input), sink, images: policy);
  }

  /// Build a PDF from image files, one per page.
  Future<void> imagesToPdf(
    List<File> images,
    File output, {
    PdfImagePage page = const PdfImagePage(),
  }) async {
    final sources = <DataSource>[
      for (final f in images) await FileSource.open(f),
    ];
    final sink = await FileSink.open(output);
    await _pdf.imagesToPdf(sources, sink, page: page);
  }

  /// Split [input]; each part is written to a file inside [dir]. Returns the
  /// files written, in order.
  Future<List<File>> split(
    File input,
    Directory dir,
    String baseName, {
    required PdfSplitRule by,
    String? password,
  }) async {
    final inSrc = await _input(input, password);
    final files = <File>[];
    await _pdf.split(
      inSrc,
      (part) async {
        final f = File(
          '${dir.path}/${baseName}_part${part.index + 1}'
          '_trang${part.start + 1}-${part.end}.pdf',
        );
        files.add(f);
        return FileSink.open(f);
      },
      by: by,
    );
    return files;
  }

  /// Re-save with a [PdfSave] — encrypt, decrypt, re-deflate.
  Future<void> resave(
    File input,
    File output, {
    PdfSave save = const PdfSave.full(),
    String? password,
  }) async {
    final inSrc = await _input(input, password);
    final sink = await FileSink.open(output);
    await _pdf.resave(inSrc, sink, save: save);
  }

  /// Encrypt [input] with [userPassword] (and the same password as owner).
  Future<void> encrypt(File input, File output, String password) => resave(
    input,
    output,
    save: PdfSave.full(
      encryption: PdfEncryption.password(
        ownerPassword: password,
        userPassword: password,
      ),
    ),
  );

  /// Remove encryption (needs [password] to open [input]).
  Future<void> decrypt(File input, File output, {String? password}) => resave(
    input,
    output,
    password: password,
    save: const PdfSave.full(encryption: PdfEncryption.remove()),
  );

  // ── Page edits ──

  Future<void> rotatePages(
    File input,
    File output, {
    required PdfRotation by,
    PdfPages pages = const PdfPages.all(),
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) => e.rotatePages(by: by, pages: pages),
    );
  }

  Future<void> reorderPages(
    File input,
    File output,
    List<int> order, {
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) => e.reorderPages(PdfPageOrder(order)),
    );
  }

  Future<void> removePages(
    File input,
    File output,
    List<int> pages, {
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) => e.removePages(PdfPages.list(pages)),
    );
  }

  /// Applies a page-plan: keeps the pages named in [order] (0-based original
  /// indices, in the desired order; omitted pages are dropped) and sets each
  /// kept page's rotation from [rotations] (missing entries keep their
  /// current rotation).
  Future<void> editPages(
    File input,
    File output, {
    required List<int> order,
    Map<int, PdfRotation> rotations = const {},
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) async {
        await e.reorderPages(PdfPageOrder(order));
        // After reorder, positions changed — rotate by new position.
        final byRotation = <PdfRotation, List<int>>{};
        for (var i = 0; i < order.length; i++) {
          final rot = rotations[order[i]];
          if (rot == null || rot == PdfRotation.r0) continue;
          byRotation.putIfAbsent(rot, () => []).add(i);
        }
        for (final entry in byRotation.entries) {
          await e.setRotation(
            entry.key,
            pages: PdfPages.list(entry.value),
          );
        }
      },
    );
  }

  /// Adds a text watermark.
  Future<void> addWatermark(
    File input,
    File output,
    String text, {
    PdfWatermarkStyle style = const PdfWatermarkStyle(),
    PdfPages pages = const PdfPages.all(),
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) => e.addWatermark(text, pages: pages, style: style),
    );
  }

  /// Stamps an image (PNG/JPEG) at [bounds] on [pages].
  Future<void> addImageStamp(
    File input,
    File output,
    Uint8List imageBytes, {
    required PdfRect bounds,
    PdfPages pages = const PdfPages.all(),
    double opacity = 1,
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) => e.addImageStamp(
        MemorySource(imageBytes),
        bounds: bounds,
        pages: pages,
        opacity: opacity,
      ),
    );
  }

  /// Stamps [text] at [position] on every page, one watermark per page —
  /// used for page numbering and header/footer.
  Future<void> numberPages(
    File input,
    File output, {
    required String pattern,
    required PdfWatermarkPosition position,
    double fontSize = 11,
    String? password,
  }) async {
    final count = (await pageInfo(input, password: password)).length;
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) async {
        for (var i = 0; i < count; i++) {
          final text = pattern
              .replaceAll('{i}', '${i + 1}')
              .replaceAll('{n}', '$count');
          await e.addWatermark(
            text,
            pages: PdfPages.single(i),
            position: position,
            style: PdfWatermarkStyle(
              fontSize: fontSize,
              opacity: 1,
              angleDegrees: 0,
              color: PdfColor.black,
            ),
          );
        }
      },
    );
  }

  /// Crops every page's margins by the given amounts in points.
  Future<void> cropMargins(
    File input,
    File output, {
    double left = 0,
    double right = 0,
    double top = 0,
    double bottom = 0,
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) => e.cropMargins(left: left, right: right, top: top, bottom: bottom),
    );
  }

  /// Reads the AcroForm fields of [file].
  Future<List<PdfFormField>> formFields(File file, {String? password}) async =>
      _pdf.read(await _input(file, password), (doc) => doc.formFields());

  /// Sets form field values and writes [output].
  Future<void> fillForm(
    File input,
    File output,
    Map<String, PdfFormFieldValue> values, {
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) async {
        for (final entry in values.entries) {
          await e.field(entry.key).setValue(entry.value);
        }
      },
    );
  }

  /// Permanently removes content under [regions] (points, y-up) on [page]
  /// and draws a black overlay over each.
  Future<PdfRedactionReport> redact(
    File input,
    File output,
    int page,
    List<PdfRect> regions, {
    String? password,
  }) async {
    final sink = await _sink(output);
    PdfRedactionReport? report;
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) async => report = await e.redact(page, regions),
    );
    return report!;
  }

  // ── Conversions ──

  /// Converts a PDF to an Office document (docx/xlsx/pptx).
  Future<void> pdfToOffice(
    File input,
    File output,
    PdfOfficeFormat format, {
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.convertToOffice(
      await _input(input, password),
      sink,
      format: format,
    );
  }

  /// Converts an Office document (docx/xlsx/pptx) to PDF.
  Future<void> officeToPdf(
    File input,
    File output,
    PdfOfficeFormat format,
  ) async {
    final source = await FileSource.open(input);
    final sink = await _sink(output);
    await _pdf.convertFromOffice(source, sink, format: format);
  }

  /// Replaces metadata.
  Future<void> setMetadata(
    File input,
    File output,
    PdfMetadata metadata, {
    String? password,
  }) async {
    final sink = await _sink(output);
    await _pdf.rewrite(
      await _input(input, password),
      sink,
      (e) => e.setMetadata(metadata),
    );
  }

  // ── Reads ──

  /// Render a single page to PNG bytes.
  Future<PdfBitmap> pageBitmap(File file, int page, {int dpi = 96}) async =>
      _pdf.read(
        PdfFile(file),
        (doc) => doc.bitmap(page, size: PdfRenderSize.dpi(dpi)),
      );

  /// Render pages to PNG files in [dir]; returns the written files.
  Future<List<File>> renderToPngs(
    File input,
    Directory dir,
    String baseName, {
    int dpi = 150,
    String? password,
  }) async {
    final files = <File>[];
    await _pdf.read(
      await _input(input, password),
      (doc) => doc.render(
        (page) async {
          final f = File(
            '${dir.path}/${baseName}_trang${page.page + 1}.png',
          );
          files.add(f);
          return FileSink.open(f);
        },
        size: PdfRenderSize.dpi(dpi),
      ),
    );
    return files;
  }

  /// Extract all text of a PDF as a string.
  Future<String> extractText(File file, {String? password}) async =>
      _pdf.read(
        await _input(file, password),
        (doc) => doc.text(format: PdfExtractionFormat.plain),
      );

  /// Page count + boxes.
  Future<List<PdfPageInfo>> pageInfo(File file, {String? password}) async =>
      _pdf.read(
        await _input(file, password),
        (doc) => doc.pageInfo(),
      );

  Future<PdfInput> _input(File file, String? password) async =>
      password == null
          ? PdfFile(file)
          : PdfInput(await FileSource.open(file), password: password);

  Future<DataSink> _sink(File output) => FileSink.open(output);
}
