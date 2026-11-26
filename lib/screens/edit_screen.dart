import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../page_overlay.dart';
import '../theme.dart';
import '../widgets.dart';

// ── Marks: what the user adds to a page ──

/// One edit on a page, in display points: the page as a reader sees it,
/// origin at its top-left, y pointing down (see [PageGeometry]).
///
/// The same [paint] draws the on-screen preview and the saved overlay, so
/// the saved page looks exactly like the edited one.
abstract class PageMark {
  const PageMark();

  /// Paints the mark on [canvas], which is scaled so one unit is one point.
  void paint(Canvas canvas);

  /// The area [paint] may cover, in display points, line widths included.
  Rect get bounds;
}

/// Text whose first line starts at [topLeft], wrapped at [maxWidth].
///
/// The engine's PDF fonts can't show Vietnamese, so text is drawn in the app
/// font and saved as part of the page image overlay.
class TextMark extends PageMark {
  const TextMark({
    required this.text,
    required this.topLeft,
    required this.fontSize,
    required this.color,
    required this.maxWidth,
  });

  /// [text] starting at the tapped point [at], centred on it vertically and
  /// moved left or up as far as needed to stay on a [page]-sized page.
  factory TextMark.place(
    String text,
    Offset at, {
    required double fontSize,
    required Color color,
    required Size page,
  }) {
    final painter = _layout(text, fontSize, color, page.width);
    final size = painter.size;
    painter.dispose();
    final left = math.max(0.0, math.min(at.dx, page.width - size.width));
    final top = math.max(
      0.0,
      math.min(at.dy - size.height / 2, page.height - size.height),
    );
    return TextMark(
      text: text,
      topLeft: Offset(left, top),
      fontSize: fontSize,
      color: color,
      maxWidth: page.width,
    );
  }

  final String text;
  final Offset topLeft;
  final double fontSize;
  final Color color;
  final double maxWidth;

  static TextPainter _layout(
    String text,
    double fontSize,
    Color color,
    double maxWidth,
  ) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.25,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  @override
  void paint(Canvas canvas) {
    final painter = _layout(text, fontSize, color, maxWidth);
    painter.paint(canvas, topLeft);
    painter.dispose();
  }

  /// The laid-out text box, with room for accents stacked on capitals,
  /// which can reach outside it.
  @override
  Rect get bounds {
    final painter = _layout(text, fontSize, color, maxWidth);
    final size = painter.size;
    painter.dispose();
    return (topLeft & size).inflate(fontSize / 2);
  }
}

/// A freehand pen stroke through [points]; a single point draws a dot.
class StrokeMark extends PageMark {
  const StrokeMark({
    required this.points,
    required this.color,
    this.width = 2.5,
  });

  final List<Offset> points;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas) {
    if (points.isEmpty) return;
    final paint = Paint()..color = color;
    if (points.length == 1) {
      canvas.drawCircle(points.first, width / 2, paint);
      return;
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Curves through the midpoints between samples smooth out the jitter of
    // finger input.
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final p = points[i];
      final next = points[i + 1];
      path.quadraticBezierTo(
        p.dx,
        p.dy,
        (p.dx + next.dx) / 2,
        (p.dy + next.dy) / 2,
      );
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  /// The smoothing curves stay between the samples, so the samples' box
  /// widened by half the pen covers the stroke and its round ends.
  @override
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var left = points.first.dx;
    var top = points.first.dy;
    var right = left;
    var bottom = top;
    for (final p in points) {
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(width / 2);
  }
}

/// A rectangle outline ("Khung").
class FrameMark extends PageMark {
  const FrameMark({required this.rect, required this.color, this.width = 2});

  final Rect rect;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas) => canvas.drawRect(
    rect,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width,
  );

  /// The outline is centred on [rect]'s edges.
  @override
  Rect get bounds => rect.inflate(width / 2);
}

/// A see-through yellow highlight ("Tô sáng").
class HighlightMark extends PageMark {
  const HighlightMark(this.rect);

  /// Highlighter yellow at 40 % so the text underneath stays readable.
  static const color = Color(0x66FFE600);

  final Rect rect;

  @override
  void paint(Canvas canvas) => canvas.drawRect(rect, Paint()..color = color);

  @override
  Rect get bounds => rect;
}

/// Longest side, in pixels, of a saved overlay. Keeps marks spread over a
/// large page (A3, drawings) within GPU texture limits and a sane amount of
/// memory.
const _maxOverlayPixels = 4096;

/// Room left around marks for their smoothed edges, in points.
const double _overlayMargin = 2;

/// The part of a [page]-sized page (display points) that [marks] cover,
/// with a small margin, cut to the page. [Rect.zero] when nothing shows.
Rect marksArea(List<PageMark> marks, Size page) {
  Rect? area;
  for (final mark in marks) {
    final bounds = mark.bounds;
    if (bounds.isEmpty) continue;
    area = area?.expandToInclude(bounds) ?? bounds;
  }
  if (area == null) return Rect.zero;
  final onPage = area.inflate(_overlayMargin).intersect(Offset.zero & page);
  return onPage.isEmpty ? Rect.zero : onPage;
}

/// Draws [marks] (display points) on a transparent overlay covering [area]
/// of the page and encodes it as PNG, at [pixelsPerPoint] or less for very
/// large areas. Whatever lies outside [area] is cut off.
Future<Uint8List> renderPageMarksPng(
  List<PageMark> marks,
  Rect area, {
  double pixelsPerPoint = 3,
}) async {
  if (area.isEmpty) {
    throw ArgumentError.value(area, 'area', 'must have a positive size');
  }
  final scale = math.min(
    pixelsPerPoint,
    _maxOverlayPixels / math.max(area.width, area.height),
  );
  final width = math.max(1, (area.width * scale).round());
  final height = math.max(1, (area.height * scale).round());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(width / area.width, height / area.height)
    ..translate(-area.left, -area.top)
    ..clipRect(area);
  for (final mark in marks) {
    mark.paint(canvas);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the page overlay');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// One image stamp for each page in [edits] (0-based index → marks) that
/// has marks showing on it, in page order. Each overlay is drawn in display
/// points, turned upright for the page's `/Rotate` and laid over only the
/// [marksArea] of its page in [pages]: a stamp annotation sits on top of
/// the page, so one covering the whole page would keep desktop readers from
/// reaching its links, form fields and text.
Future<List<ImageStamp>> buildEditStamps(
  List<PdfPageInfo> pages,
  Map<int, List<PageMark>> edits, {
  double pixelsPerPoint = 3,
}) async {
  final indices = [
    for (final MapEntry(:key, :value) in edits.entries)
      if (value.isNotEmpty) key,
  ]..sort();
  final stamps = <ImageStamp>[];
  for (final index in indices) {
    final g = PageGeometry(pages[index]);
    final marks = edits[index]!;
    final area = marksArea(marks, Size(g.width, g.height));
    if (area.isEmpty) continue;
    final png = await renderPageMarksPng(
      marks,
      area,
      pixelsPerPoint: pixelsPerPoint,
    );
    stamps.add((
      png: await g.uprightForPage(png),
      bounds: g.toPdf(area),
      pages: [index],
      opacity: 1.0,
    ));
  }
  return stamps;
}

// ── Screen ──

/// Edit PDF: add text, freehand ink, frames and highlights on any pages, then
/// save. Each edited page gets one image overlay drawn by Flutter, since the
/// engine can't write Vietnamese text.
class EditScreen extends StatefulWidget {
  const EditScreen({super.key});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

enum _Tool {
  text('Chữ', Icons.text_fields_rounded, 'Chạm vào trang ở chỗ muốn thêm chữ.'),
  pen('Vẽ', Icons.draw_outlined, 'Dùng ngón tay vẽ hoặc viết lên trang.'),
  frame('Khung', Icons.crop_square_rounded, 'Kéo chéo trên trang để vẽ khung.'),
  highlight(
    'Tô sáng',
    Icons.border_color_outlined,
    'Kéo qua dòng chữ để tô sáng (màu vàng).',
  );

  const _Tool(this.label, this.icon, this.hint);

  final String label;
  final IconData icon;
  final String hint;
}

/// Ink colours: page content, so they are fixed rather than themed.
enum _Ink {
  black('Đen', Color(0xFF111111)),
  red('Đỏ', Color(0xFFD32F2F)),
  blue('Xanh', Color(0xFF1E4FD8));

  const _Ink(this.label, this.color);

  final String label;
  final Color color;
}

/// Text sizes in points, roughly small print, body text and a heading.
enum _TextSize {
  small('Nhỏ', 10),
  medium('Vừa', 13),
  large('Lớn', 18);

  const _TextSize(this.label, this.points);

  final String label;
  final double points;
}

typedef _TextEntry = ({String text, _TextSize size});

/// Line widths and drag limits, in points.
const double _penWidth = 2.5;
const double _frameWidth = 2;

/// Drags shorter than this are stray touches, not frames or highlights.
const double _minDrag = 4;

/// Frames and highlights are at least this tall and wide, so a drag along
/// a line of text covers the line.
const double _minRectSide = 14;

/// A page's marks, plus the earlier versions "Hoàn tác" steps back through.
class _PageEdits {
  List<PageMark> marks = const [];
  final List<List<PageMark>> history = [];
}

class _EditScreenState extends State<EditScreen> {
  File? _input;
  List<PdfPageInfo> _pages = const [];
  bool _opening = false;

  /// The page on screen (0-based) and its rendered bitmap. The image is
  /// owned here and disposed whenever it's replaced.
  int _page = 0;
  ui.Image? _pageImage;
  bool _pageFailed = false;

  /// Bumped on every page change, so a slow render of a page the user has
  /// already left is dropped.
  int _loadToken = 0;
  Timer? _loadTimer;

  final Map<int, _PageEdits> _edits = {};
  _Tool _tool = _Tool.text;
  _Ink _ink = _Ink.black;
  _TextSize _textSize = _TextSize.medium;

  /// The mark under the finger right now. It repaints on its own, so a
  /// stroke never rebuilds the screen.
  final _draft = ValueNotifier<PageMark?>(null);
  List<Offset>? _stroke;
  Offset? _dragOrigin;

  /// Counts edits, so unsaved work is detected and an unchanged document
  /// isn't saved twice.
  int _revision = 0;
  int _savedRevision = 0;
  bool _running = false;
  File? _output;
  int _outputPages = 0;
  String? _error;

  @override
  void dispose() {
    _loadTimer?.cancel();
    _draft.dispose();
    _pageImage?.dispose();
    super.dispose();
  }

  List<PageMark> get _marks => _edits[_page]?.marks ?? const [];

  bool get _hasEdits => _edits.values.any((e) => e.marks.isNotEmpty);

  bool get _dirty => _revision != _savedRevision && _hasEdits;

  // ── File and pages ──

  Future<void> _pick() async {
    if (_running || _opening || !await _confirmDiscard()) return;
    final List<File>? files;
    try {
      files = await pickPdfs();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
      return;
    }
    if (files == null || !mounted) return;
    final file = files.first;
    _cancelDrag();
    _loadTimer?.cancel();
    final token = ++_loadToken;
    setState(() {
      _input = file;
      _pages = const [];
      _page = 0;
      _setPageImage(null);
      _pageFailed = false;
      _edits.clear();
      _revision = _savedRevision = 0;
      _output = null;
      _error = null;
      _opening = true;
    });
    try {
      final pages = await PdfEngine.instance.pageInfo(file);
      if (!mounted || token != _loadToken) return;
      if (pages.isEmpty) {
        setState(() {
          _input = null;
          _opening = false;
          _error = 'File này không có trang nào.';
        });
        return;
      }
      setState(() {
        _pages = pages;
        _opening = false;
      });
      await _loadPage(0, token);
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _input = null;
        _opening = false;
        _error = friendlyError(e);
      });
    }
  }

  void _goTo(int page) {
    if (_running || page < 0 || page >= _pages.length || page == _page) {
      return;
    }
    _cancelDrag();
    _loadTimer?.cancel();
    final token = ++_loadToken;
    setState(() {
      _page = page;
      _setPageImage(null);
      _pageFailed = false;
      _error = null;
    });
    // Debounced, so quick taps on ‹ › render only the page the user stops on.
    _loadTimer = Timer(
      const Duration(milliseconds: 150),
      () => _loadPage(page, token),
    );
  }

  Future<void> _loadPage(int page, int token) async {
    final input = _input;
    if (input == null) return;
    try {
      final bitmap = await PdfEngine.instance.pageBitmap(
        input,
        page,
        dpi: _displayDpi(PageGeometry(_pages[page])),
      );
      final image = await _decodePng(bitmap.bytes);
      if (!mounted || token != _loadToken) {
        image.dispose();
        return;
      }
      setState(() => _setPageImage(image));
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _pageFailed = true;
        _error = friendlyError(e);
      });
    }
  }

  /// Replaces the page bitmap. [RawImage] keeps its own clone, so the old
  /// handle can be released right away.
  void _setPageImage(ui.Image? image) {
    _pageImage?.dispose();
    _pageImage = image;
  }

  // ── Editing ──

  void _commit(int page, PageMark mark) {
    setState(() {
      final edits = _edits.putIfAbsent(page, _PageEdits.new);
      edits.history.add(edits.marks);
      edits.marks = [...edits.marks, mark];
      _revision++;
      _error = null;
    });
  }

  void _undo() {
    final edits = _edits[_page];
    if (edits == null || edits.history.isEmpty) return;
    setState(() {
      edits.marks = edits.history.removeLast();
      _revision++;
    });
  }

  /// Clears the page; "Hoàn tác" brings the marks back.
  void _clearPage() {
    final edits = _edits[_page];
    if (edits == null || edits.marks.isEmpty) return;
    setState(() {
      edits.history.add(edits.marks);
      edits.marks = const [];
      _revision++;
    });
  }

  Future<void> _addText(Offset at, Size pageSize) async {
    final page = _page;
    final entry = await showDialog<_TextEntry>(
      context: context,
      builder: (_) => _TextDialog(size: _textSize),
    );
    if (entry == null || !mounted || page != _page) return;
    _textSize = entry.size;
    _commit(
      page,
      TextMark.place(
        entry.text,
        at,
        fontSize: entry.size.points,
        color: _ink.color,
        page: pageSize,
      ),
    );
  }

  void _onDragStart(Offset at) {
    switch (_tool) {
      case _Tool.pen:
        final stroke = [at];
        _stroke = stroke;
        _draft.value = StrokeMark(
          points: stroke,
          color: _ink.color,
          width: _penWidth,
        );
      case _Tool.frame || _Tool.highlight:
        _dragOrigin = at;
        _draft.value = null;
      case _Tool.text:
        break;
    }
  }

  void _onDragUpdate(Offset at, Size page) {
    final stroke = _stroke;
    if (stroke != null) {
      if ((at - stroke.last).distance < 0.5) return;
      stroke.add(at);
      _draft.value = StrokeMark(
        points: stroke,
        color: _ink.color,
        width: _penWidth,
      );
      return;
    }
    final origin = _dragOrigin;
    if (origin != null) _draft.value = _rectMark(origin, at, page);
  }

  void _onDragEnd(int page) {
    final stroke = _stroke;
    final draft = _draft.value;
    _cancelDrag();
    if (stroke != null) {
      _commit(
        page,
        StrokeMark(
          points: List.unmodifiable(stroke),
          color: _ink.color,
          width: _penWidth,
        ),
      );
    } else if (draft != null) {
      _commit(page, draft);
    }
  }

  void _cancelDrag() {
    _stroke = null;
    _dragOrigin = null;
    _draft.value = null;
  }

  /// The frame or highlight for a drag from [a] to [b], kept on the page.
  PageMark? _rectMark(Offset a, Offset b, Size page) {
    final dragged = Rect.fromPoints(a, b);
    if (dragged.longestSide < _minDrag) return null;
    final rect = Rect.fromCenter(
      center: dragged.center,
      width: math.max(dragged.width, _minRectSide),
      height: math.max(dragged.height, _minRectSide),
    ).intersect(Offset.zero & page);
    if (rect.isEmpty) return null;
    return _tool == _Tool.highlight
        ? HighlightMark(rect)
        : FrameMark(rect: rect, color: _ink.color, width: _frameWidth);
  }

  // ── Saving ──

  void _onSavePressed() {
    final output = _output;
    // Nothing changed since the last save: show that file again rather
    // than writing a duplicate.
    if (!_dirty && output != null && output.existsSync()) {
      _showResult(output, _outputPages);
    } else {
      _save();
    }
  }

  Future<void> _save() async {
    final input = _input;
    final edits = {
      for (final MapEntry(:key, :value) in _edits.entries)
        if (value.marks.isNotEmpty) key: value.marks,
    };
    if (input == null || edits.isEmpty || _running) return;
    _cancelDrag();
    final revision = _revision;
    setState(() {
      _running = true;
      _error = null;
    });
    File? written;
    try {
      final stamps = await buildEditStamps(_pages, edits);
      final out = await outputFile(
        '${fileBaseName(input.path)}_dasua_noidung',
        'pdf',
      );
      written = out;
      await PdfEngine.instance.addImageStamps(input, out, stamps);
      if (!mounted) return;
      setState(() {
        _output = out;
        _outputPages = stamps.length;
        _savedRevision = revision;
      });
      _showResult(out, stamps.length);
    } catch (e) {
      // Keep a half-written file out of the user's file list.
      deleteQuietly(written);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _showResult(File file, int pageCount) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResultCard(file: file, extra: 'Đã sửa $pageCount trang'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Sửa tiếp'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// True when there is nothing unsaved or the user agrees to drop it.
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ chỉnh sửa chưa lưu?'),
        content: const Text(
          'Bạn chưa bấm "Lưu PDF". Nếu tiếp tục, những gì vừa thêm sẽ mất.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ở lại'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ chỉnh sửa'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  /// Back with unsaved edits asks first, so a stray edge swipe while
  /// drawing doesn't throw the work away. While saving there is nothing to
  /// ask: the edits are being written, so back waits for that.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    if (_running) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Đang lưu PDF, vui lòng chờ trong giây lát.'),
          ),
        );
      return;
    }
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = _input != null && _pages.isNotEmpty;
    return PopScope<Object?>(
      canPop: !_dirty && !_running,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        // Only dialogs take text here; keep the page still under the keyboard.
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text('Chỉnh sửa PDF'),
          actions: [
            if (editing)
              IconButton(
                tooltip: 'Chọn file khác',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: _running ? null : _pick,
              ),
          ],
        ),
        body: editing ? _editor(theme) : _start(theme),
      ),
    );
  }

  Widget _start(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Thêm chữ, vẽ, đóng khung hoặc tô sáng lên trang.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        PickTile(
          icon: Icons.picture_as_pdf_outlined,
          label: 'Chọn PDF cần sửa',
          picked: _input == null ? null : fileBaseName(_input!.path),
          onPick: _pick,
        ),
        const SizedBox(height: 16),
        if (_opening) const RunningPane(message: 'Đang mở file…'),
        if (_error != null) ErrorBanner(message: _error!),
      ],
    );
  }

  Widget _editor(ThemeData theme) {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, box) {
          // The page itself never scrolls, so drawing doesn't fight a scroll
          // view. The controls scroll on their own when space runs short
          // (landscape, very large text), which leaves the page at least
          // 40 % of the height and keeps the layout from overflowing.
          final cap = box.maxHeight * 0.3;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _capped(cap, _toolbar(theme)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: _pageView(theme.colorScheme),
                ),
              ),
              _capped(cap, _bottomBar(theme)),
            ],
          );
        },
      ),
    );
  }

  /// Two of these sit on screen at once, so neither may claim the primary
  /// scroll controller.
  static Widget _capped(double maxHeight, Widget child) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: SingleChildScrollView(primary: false, child: child),
  );

  Widget _toolbar(ThemeData theme) {
    final scheme = theme.colorScheme;
    final busy = _running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_Tool>(
            segments: [
              for (final tool in _Tool.values)
                ButtonSegment(
                  value: tool,
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tool.icon, size: 20),
                      const SizedBox(height: 2),
                      // Shrinks rather than breaking a word at large text
                      // sizes on narrow phones.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(tool.label, maxLines: 1),
                      ),
                    ],
                  ),
                ),
            ],
            selected: {_tool},
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            style: _segmentStyle(scheme),
            onSelectionChanged: busy
                ? null
                : (selection) {
                    _cancelDrag();
                    setState(() => _tool = selection.first);
                  },
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ink in _Ink.values)
                    _InkSwatch(
                      ink: ink,
                      selected: ink == _ink,
                      // The highlighter is always yellow.
                      onTap: busy || _tool == _Tool.highlight
                          ? null
                          : () => setState(() => _ink = ink),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed:
                        !busy && (_edits[_page]?.history.isNotEmpty ?? false)
                        ? _undo
                        : null,
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Hoàn tác'),
                  ),
                  IconButton(
                    onPressed: !busy && _marks.isNotEmpty ? _clearPage : null,
                    tooltip: 'Xóa hết trang này',
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pageView(ColorScheme scheme) {
    final g = PageGeometry(_pages[_page]);
    final page = Size(g.width, g.height);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (page.isEmpty || constraints.biggest.isEmpty) {
          return const SizedBox.shrink();
        }
        final box = applyBoxFit(
          BoxFit.contain,
          page,
          constraints.biggest,
        ).destination;
        // Widget pixels → display points.
        final scale = box.width / page.width;
        final image = _pageImage;
        final active = image != null && !_running;
        final tap = active && _tool == _Tool.text;
        final drag = active && _tool != _Tool.text;
        final index = _page;
        return Center(
          child: Semantics(
            label: 'Trang ${index + 1}',
            child: SizedBox.fromSize(
              size: box,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.5),
                  ),
                ),
                child: ClipRect(
                  // Only the active tool's callbacks are set: with a lone
                  // pan recognizer a stroke starts right at the touch point
                  // instead of after the drag slop.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: tap
                        ? (d) => _addText(d.localPosition / scale, page)
                        : null,
                    onPanStart: drag
                        ? (d) => _onDragStart(d.localPosition / scale)
                        : null,
                    onPanUpdate: drag
                        ? (d) => _onDragUpdate(d.localPosition / scale, page)
                        : null,
                    onPanEnd: drag ? (_) => _onDragEnd(index) : null,
                    onPanCancel: drag ? _cancelDrag : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image != null)
                          ColoredBox(
                            color: Colors.white,
                            child: RawImage(image: image, fit: BoxFit.fill),
                          )
                        else
                          ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Center(
                              child: _pageFailed
                                  ? Icon(
                                      Icons.broken_image_outlined,
                                      color: scheme.onSurfaceVariant,
                                    )
                                  : const CircularProgressIndicator(),
                            ),
                          ),
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: _MarksPainter(_marks, scale),
                          ),
                        ),
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: _DraftPainter(_draft, scale),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomBar(ThemeData theme) {
    final count = _pages.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_running)
            const RunningPane(message: 'Đang lưu PDF…')
          else ...[
            // How to use the chosen tool, as a caption under the page.
            Text(
              _tool.hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (count > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Trang trước',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                  ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: _pageButton(count),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Trang sau',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _page < count - 1
                        ? () => _goTo(_page + 1)
                        : null,
                  ),
                ],
              ),
            if (_error != null) ErrorBanner(message: _error!),
            const SizedBox(height: 4),
            RunButton(
              label: 'Lưu PDF',
              enabled: _hasEdits,
              onPressed: _onSavePressed,
            ),
          ],
        ],
      ),
    );
  }

  /// "Trang 2/10", which opens the list of pages for jumping in long files.
  /// The list is built only when opened, so drawing never rebuilds it.
  Widget _pageButton(int count) {
    return TextButton(
      onPressed: _choosePage,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'Trang ${_page + 1}/$count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down_rounded),
        ],
      ),
    );
  }

  Future<void> _choosePage() async {
    final edited = {
      for (final MapEntry(:key, :value) in _edits.entries)
        if (value.marks.isNotEmpty) key,
    };
    final page = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _PageList(count: _pages.length, current: _page, edited: edited),
    );
    if (page != null && mounted) _goTo(page);
  }
}

/// The pages to jump to, opened at the current one; edited pages say so.
/// Rows are built as they scroll into view.
class _PageList extends StatefulWidget {
  const _PageList({
    required this.count,
    required this.current,
    required this.edited,
  });

  final int count;

  /// 0-based, like [edited].
  final int current;
  final Set<int> edited;

  @override
  State<_PageList> createState() => _PageListState();
}

class _PageListState extends State<_PageList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Every row is as tall as the prototype, so once the list is laid out
    // its length gives the current page's offset.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final viewport = position.viewportDimension;
      final row = (position.maxScrollExtent + viewport) / widget.count;
      final centred = (widget.current + 0.5) * row - viewport / 2;
      _scroll.jumpTo(centred.clamp(0.0, position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _row(BuildContext context, int index) => ListTile(
    selected: index == widget.current,
    title: Text(
      widget.edited.contains(index)
          ? 'Trang ${index + 1} · đã sửa'
          : 'Trang ${index + 1}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => Navigator.of(context).pop(index),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.builder(
        controller: _scroll,
        // Short files get a short sheet.
        shrinkWrap: true,
        itemCount: widget.count,
        prototypeItem: _row(context, widget.count - 1),
        itemBuilder: _row,
      ),
    );
  }
}

/// Segmented choices with a solid fill on the chosen one, so they need no
/// check mark: on narrow phones the mark squeezes labels onto two lines.
ButtonStyle _segmentStyle(ColorScheme scheme) =>
    SegmentedButton.styleFrom(
      selectedBackgroundColor: scheme.primary,
      selectedForegroundColor: scheme.onPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    ).copyWith(
      // Icons otherwise default to `primary`, which would vanish on the fill.
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: 0.38);
        }
        return states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurface;
      }),
    );

/// About 110 dpi for the page on screen; less for big pages, so the
/// bitmap's long side stays near 2000 px.
int _displayDpi(PageGeometry g) {
  final longSide = math.max(g.width, g.height);
  if (longSide <= 0) return 110;
  return math.min(110, math.max(24, (2000 * 72 / longSide).floor()));
}

Future<ui.Image> _decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

class _MarksPainter extends CustomPainter {
  const _MarksPainter(this.marks, this.scale);

  final List<PageMark> marks;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    for (final mark in marks) {
      mark.paint(canvas);
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) =>
      !identical(old.marks, marks) || old.scale != scale;
}

class _DraftPainter extends CustomPainter {
  _DraftPainter(this.draft, this.scale) : super(repaint: draft);

  final ValueNotifier<PageMark?> draft;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final mark = draft.value;
    if (mark == null) return;
    canvas.scale(scale);
    mark.paint(canvas);
  }

  @override
  bool shouldRepaint(_DraftPainter old) =>
      old.draft != draft || old.scale != scale;
}

/// A round colour swatch; the selected one gets a ring and a check mark.
class _InkSwatch extends StatelessWidget {
  const _InkSwatch({
    required this.ink,
    required this.selected,
    required this.onTap,
  });

  final _Ink ink;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: 'Màu ${ink.label.toLowerCase()}',
      excludeSemantics: true,
      child: Tooltip(
        message: ink.label,
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Opacity(
                opacity: enabled ? 1 : 0.35,
                child: Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ink.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.6),
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the text to add and its size.
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.size});

  final _TextSize size;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _controller = TextEditingController();
  late _TextSize _size = widget.size;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trimRight();
    if (text.trim().isEmpty) return;
    Navigator.of(context).pop<_TextEntry>((text: text, size: _size));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Thêm chữ'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Nhập chữ cần thêm'),
            ),
            const SizedBox(height: 16),
            Text('Cỡ chữ', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<_TextSize>(
              segments: [
                for (final size in _TextSize.values)
                  ButtonSegment(
                    value: size,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(size.label, maxLines: 1),
                    ),
                  ),
              ],
              selected: {_size},
              showSelectedIcon: false,
              style: _segmentStyle(theme.colorScheme),
              onSelectionChanged: (selection) =>
                  setState(() => _size = selection.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            onPressed: _controller.text.trim().isEmpty ? null : _submit,
            child: const Text('Thêm'),
          ),
        ),
      ],
    );
  }
}
