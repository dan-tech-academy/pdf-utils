import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';

/// One image to stamp: [png] fills [bounds] (PDF points, y up) on each of
/// [pages] (0-based) at [opacity].
typedef ImageStamp = ({
  Uint8List png,
  PdfRect bounds,
  List<int> pages,
  double opacity,
});

/// Shared wrapper around the pdf_manipulator engine. `PdfDocument` and
/// `PdfEditor` are not part of the package's public exports, so every op is
/// expressed here as a concrete method — closure parameter types stay
/// inferred inside this file.
///
/// The engine never closes an output sink or a [FileSource] it is handed,
/// so every write goes through [_writeTo] and every source opened here is
/// closed here. Sinks returned per part (split, image extraction) are the
/// engine's to close.
class PdfEngine {
  PdfEngine._();
  static final PdfEngine instance = PdfEngine._();

  final Pdf _pdf = Pdf();

  Future<PdfDocumentInfo> info(File file) => _pdf.info(PdfFile(file));

  /// Merge PDFs in order into [output].
  Future<void> merge(List<File> inputs, File output) => _writeTo(
    output,
    (sink) => _pdf.merge(inputs.map((f) => PdfFile(f)).toList(), sink),
  );

  /// Compress with the given image policy; never grows the file.
  Future<void> compress(File input, File output, PdfImagePolicy policy) =>
      _writeTo(
        output,
        (sink) => _pdf.compress(PdfFile(input), sink, images: policy),
      );

  /// Build a PDF from image files, one per page.
  Future<void> imagesToPdf(
    List<File> images,
    File output, {
    PdfImagePage page = const PdfImagePage(),
  }) async {
    final sources = <FileSource>[];
    try {
      for (final f in images) {
        sources.add(await FileSource.open(f));
      }
      await _writeTo(
        output,
        (sink) => _pdf.imagesToPdf(sources, sink, page: page),
      );
    } finally {
      for (final s in sources) {
        await s.close();
      }
    }
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
    final files = <File>[];
    await _pdf.split(_input(input, password), (part) async {
      final f = File(
        '${dir.path}/${baseName}_part${part.index + 1}'
        '_trang${part.start + 1}-${part.end}.pdf',
      );
      files.add(f);
      return FileSink.open(f);
    }, by: by);
    return files;
  }

  /// Re-save with a [PdfSave] — encrypt, decrypt, re-deflate.
  Future<void> resave(
    File input,
    File output, {
    PdfSave save = const PdfSave.full(),
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.resave(_input(input, password), sink, save: save),
  );

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

  /// Rewrites [input] in full. The engine rebuilds a damaged
  /// cross-reference table when it opens a file, so this recovers PDFs with
  /// broken offsets or a lost tail.
  Future<void> repair(File input, File output, {String? password}) =>
      resave(input, output, password: password);

  /// Converts [input] to PDF/A-2b for archiving and validates the result.
  /// PDF/A forbids encryption, so any (owner-only) lock is removed.
  Future<PdfValidationReport> convertToPdfA(
    File input,
    File output, {
    String? password,
  }) async {
    await _writeTo(
      output,
      (sink) => _pdf.rewrite(
        _input(input, password),
        sink,
        (e) => e.convertToPdfA(),
        save: const PdfSave.full(encryption: PdfEncryption.remove()),
      ),
    );
    return _pdf.read(PdfFile(output), (doc) => doc.validatePdfA());
  }

  // ── Page edits ──

  Future<void> rotatePages(
    File input,
    File output, {
    required PdfRotation by,
    PdfPages pages = const PdfPages.all(),
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(
      _input(input, password),
      sink,
      (e) => e.rotatePages(by: by, pages: pages),
    ),
  );

  Future<void> reorderPages(
    File input,
    File output,
    List<int> order, {
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(
      _input(input, password),
      sink,
      (e) => e.reorderPages(PdfPageOrder(order)),
    ),
  );

  Future<void> removePages(
    File input,
    File output,
    List<int> pages, {
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(
      _input(input, password),
      sink,
      (e) => e.removePages(PdfPages.list(pages)),
    ),
  );

  /// Keeps only [pages] (0-based), in document order; drops the rest.
  Future<void> keepPages(
    File input,
    File output,
    List<int> pages, {
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(
      _input(input, password),
      sink,
      (e) => e.keepPages(PdfPages.list(pages)),
    ),
  );

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
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(_input(input, password), sink, (e) async {
      await e.reorderPages(PdfPageOrder(order));
      // After reorder, positions changed — rotate by new position.
      final byRotation = <PdfRotation, List<int>>{};
      for (var i = 0; i < order.length; i++) {
        final rot = rotations[order[i]];
        if (rot == null || rot == PdfRotation.r0) continue;
        byRotation.putIfAbsent(rot, () => []).add(i);
      }
      for (final entry in byRotation.entries) {
        await e.setRotation(entry.key, pages: PdfPages.list(entry.value));
      }
    }),
  );

  /// Stamps an image (PNG/JPEG) at [bounds] on [pages].
  Future<void> addImageStamp(
    File input,
    File output,
    Uint8List imageBytes, {
    required PdfRect bounds,
    PdfPages pages = const PdfPages.all(),
    double opacity = 1,
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(
      _input(input, password),
      sink,
      (e) => e.addImageStamp(
        MemorySource(imageBytes),
        bounds: bounds,
        pages: pages,
        opacity: opacity,
      ),
    ),
  );

  /// Stamps every entry of [stamps] in one rewrite. Give pages that share an
  /// image one entry, so the image is embedded once.
  ///
  /// This is also how tools write text onto pages: the engine's own text
  /// (watermarks, builder text) uses PDF base fonts that cannot draw
  /// Vietnamese, so text is rendered with `renderTextImage` and stamped.
  Future<void> addImageStamps(
    File input,
    File output,
    List<ImageStamp> stamps, {
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(_input(input, password), sink, (e) async {
      for (final s in stamps) {
        await e.addImageStamp(
          MemorySource(s.png),
          bounds: s.bounds,
          pages: PdfPages.list(s.pages),
          opacity: s.opacity,
        );
      }
    }),
  );

  /// Crops every page's margins by the given amounts in points.
  Future<void> cropMargins(
    File input,
    File output, {
    double left = 0,
    double right = 0,
    double top = 0,
    double bottom = 0,
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(
      _input(input, password),
      sink,
      (e) => e.cropMargins(left: left, right: right, top: top, bottom: bottom),
    ),
  );

  /// Reads the AcroForm fields of [file].
  Future<List<PdfFormField>> formFields(File file, {String? password}) =>
      _pdf.read(_input(file, password), (doc) => doc.formFields());

  /// Sets form field values and writes [output].
  Future<void> fillForm(
    File input,
    File output,
    Map<String, PdfFormFieldValue> values, {
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(_input(input, password), sink, (e) async {
      for (final entry in values.entries) {
        await e.field(entry.key).setValue(entry.value);
      }
    }),
  );

  /// Permanently removes content under [regions] (points, y-up) on [page]
  /// and draws a black overlay over each.
  Future<PdfRedactionReport> redact(
    File input,
    File output,
    int page,
    List<PdfRect> regions, {
    String? password,
  }) async {
    PdfRedactionReport? report;
    await _writeTo(
      output,
      (sink) => _pdf.rewrite(
        _input(input, password),
        sink,
        (e) async => report = await e.redact(page, regions),
      ),
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
  }) => _writeTo(
    output,
    (sink) =>
        _pdf.convertToOffice(_input(input, password), sink, format: format),
  );

  /// Converts an Office document (docx/xlsx/pptx) to PDF.
  Future<void> officeToPdf(
    File input,
    File output,
    PdfOfficeFormat format,
  ) async {
    final source = await FileSource.open(input);
    try {
      await _writeTo(
        output,
        (sink) => _pdf.convertFromOffice(source, sink, format: format),
      );
    } finally {
      await source.close();
    }
  }

  /// Replaces metadata.
  Future<void> setMetadata(
    File input,
    File output,
    PdfMetadata metadata, {
    String? password,
  }) => _writeTo(
    output,
    (sink) => _pdf.rewrite(
      _input(input, password),
      sink,
      (e) => e.setMetadata(metadata),
    ),
  );

  // ── Reads ──

  /// Render a single page to PNG bytes.
  Future<PdfBitmap> pageBitmap(File file, int page, {int dpi = 96}) =>
      _pdf.read(
        PdfFile(file),
        (doc) => doc.bitmap(page, size: PdfRenderSize.dpi(dpi)),
      );

  /// Extract all text of a PDF as a string, as plain text or Markdown.
  Future<String> extractText(
    File file, {
    String? password,
    PdfExtractionFormat format = PdfExtractionFormat.plain,
  }) => _pdf.read(_input(file, password), (doc) => doc.text(format: format));

  /// Plain text of every page, in page order.
  Future<List<String>> pageTexts(File file, {String? password}) =>
      _pdf.read(_input(file, password), (doc) async {
        final count = (await doc.pageInfo()).length;
        return [
          for (var i = 0; i < count; i++)
            await doc.text(
              pages: PdfPages.single(i),
              format: PdfExtractionFormat.plain,
            ),
        ];
      });

  /// Writes every image embedded in [input] to [dir] as the file holds it:
  /// JPEG as .jpg, JPEG 2000 as .jp2, everything else as .png. Returns the
  /// files written, in page order.
  Future<List<File>> extractImages(
    File input,
    Directory dir,
    String baseName, {
    String? password,
  }) async {
    final files = <File>[];
    await _pdf.read(
      _input(input, password),
      (doc) => doc.extractImages((image) {
        final ext = switch (image.encoding) {
          PdfImageEncoding.jpeg => 'jpg',
          PdfImageEncoding.jpx => 'jp2',
          _ => 'png',
        };
        final f = File(
          '${dir.path}/${baseName}_trang${image.page + 1}'
          '_anh${image.index + 1}.$ext',
        );
        files.add(f);
        return FileSink.open(f);
      }),
    );
    return files;
  }

  /// Page count + boxes.
  Future<List<PdfPageInfo>> pageInfo(File file, {String? password}) =>
      _pdf.read(_input(file, password), (doc) => doc.pageInfo());

  PdfInput _input(File file, String? password) =>
      PdfFile(file, password: password);

  /// Opens [output], runs [write] on it and always closes it.
  Future<void> _writeTo(
    File output,
    Future<void> Function(DataSink sink) write,
  ) async {
    final sink = await FileSink.open(output);
    try {
      await write(sink);
    } finally {
      await sink.close();
    }
  }
}
