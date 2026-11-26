import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../page_overlay.dart';
import '../widgets.dart';

/// Widest a grid tile gets, in logical pixels, and its width : height.
const double _tileExtent = 140;
const double _tileAspect = 0.75;

/// The box, in pixels, a thumbnail is rendered to fit: twice the widest
/// tile ([_tileExtent]), in the tile's shape. Sharp enough on most phones,
/// and a few hundred KB decoded however large the page is.
const int _thumbWidth = 280;
const double _thumbHeight = _thumbWidth / _tileAspect;

/// The render resolution that fits page [info] in a thumbnail box.
int _thumbDpi(PdfPageInfo info) {
  final g = PageGeometry(info);
  if (g.width <= 0 || g.height <= 0) return 50;
  final scale = math.min(_thumbWidth / g.width, _thumbHeight / g.height);
  return math.max(1, (scale * 72).floor());
}

/// What [SelectPagesScreen] does with the pages the user taps.
enum SelectPagesMode {
  /// Delete the tapped pages and keep the rest.
  remove,

  /// Copy the tapped pages into a new file; the source stays as it is.
  extract,
}

/// Removes or extracts pages chosen by tapping their thumbnails.
class SelectPagesScreen extends StatefulWidget {
  const SelectPagesScreen({super.key, required this.mode});

  final SelectPagesMode mode;

  @override
  State<SelectPagesScreen> createState() => _SelectPagesScreenState();
}

class _SelectPagesScreenState extends State<SelectPagesScreen> {
  /// Longer files make a grid too long to tap through and too slow to
  /// render page by page.
  static const _maxPages = 200;

  final _scroll = ScrollController();
  File? _input;

  /// One thumbnail per page; null until rendered, or when rendering failed.
  List<Uint8List?> _thumbs = const [];

  /// Selected pages, 0-based.
  final _selected = <int>{};

  /// Bumped on every pick, so the thumbnail loop of an older file stops.
  int _loadId = 0;
  bool _opening = false;
  bool _running = false;
  File? _output;
  String? _outputNote;
  String? _error;

  bool get _isRemove => widget.mode == SelectPagesMode.remove;
  int get _pageCount => _thumbs.length;

  /// Deleting every page would leave a PDF with nothing in it.
  bool get _removesAll =>
      _isRemove && _pageCount > 0 && _selected.length == _pageCount;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_running) return;
    final files = await pickPdfs();
    if (!mounted || files == null || files.isEmpty) return;
    final file = files.first;
    final id = ++_loadId;
    setState(() {
      _input = file;
      _thumbs = const [];
      _selected.clear();
      _opening = true;
      _output = null;
      _error = null;
    });
    final List<PdfPageInfo> pages;
    try {
      pages = await PdfEngine.instance.pageInfo(file);
      if (!mounted || id != _loadId) return;
      final count = pages.length;
      if (count == 0 || count > _maxPages) {
        setState(() {
          _opening = false;
          _error = count == 0
              ? 'File này không có trang nào.'
              : 'File có $count trang, quá dài để hiện từng trang '
                    '(tối đa $_maxPages trang). Hãy dùng "Tách PDF" để chia '
                    'nhỏ trước.';
        });
        return;
      }
      setState(() {
        _opening = false;
        _thumbs = List<Uint8List?>.filled(count, null);
      });
    } catch (e) {
      if (mounted && id == _loadId) {
        setState(() {
          _opening = false;
          _error = friendlyError(e);
        });
      }
      return;
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _renderThumbs(file, pages, id);
  }

  /// Renders thumbnails one page at a time, so they show up as they are
  /// ready without flooding the engine with parallel renders. Each is sized
  /// from its page, since a fixed resolution makes huge bitmaps of big
  /// pages (posters, drawings, photos saved as pages).
  Future<void> _renderThumbs(File file, List<PdfPageInfo> pages, int id) async {
    for (var i = 0; i < pages.length; i++) {
      Uint8List? png;
      try {
        final bitmap = await PdfEngine.instance.pageBitmap(
          file,
          i,
          dpi: _thumbDpi(pages[i]),
        );
        png = bitmap.bytes;
      } catch (_) {
        // The page keeps its numbered placeholder and can still be picked;
        // a truly broken file fails the run with a clear message.
      }
      if (!mounted || id != _loadId) return;
      if (png != null) setState(() => _thumbs[i] = png);
    }
  }

  void _toggle(int page) {
    setState(() {
      if (!_selected.remove(page)) _selected.add(page);
      _error = null;
    });
  }

  void _selectAll() {
    setState(() {
      _selected.addAll(List<int>.generate(_pageCount, (i) => i));
      _error = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _error = null;
    });
  }

  Future<void> _run() async {
    final input = _input;
    // When every page is selected for removal, the action bar disables the
    // button and says why.
    if (input == null || _selected.isEmpty || _removesAll || _running) return;
    final pages = _selected.toList()..sort();
    final total = _pageCount;
    setState(() {
      _running = true;
      _error = null;
      _output = null;
    });
    File? out;
    try {
      out = await outputFile(
        '${fileBaseName(input.path)}_${_isRemove ? 'xoatrang' : 'trichtrang'}',
        'pdf',
      );
      if (_isRemove) {
        await PdfEngine.instance.removePages(input, out, pages);
      } else {
        await PdfEngine.instance.keepPages(input, out, pages);
      }
      if (!mounted) return;
      setState(() {
        _output = out;
        _outputNote = _isRemove
            ? 'Đã xóa ${pages.length} trang, còn ${total - pages.length} trang'
            : 'File mới gồm ${pages.length} trang';
      });
    } catch (e) {
      deleteQuietly(out);
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
    _revealEnd();
  }

  /// Brings the error or result into view: both sit below the page grid.
  void _revealEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPages = _pageCount > 0;
    return Scaffold(
      appBar: AppBar(title: Text(_isRemove ? 'Xóa trang' : 'Trích trang')),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PickTile(
                    icon: Icons.picture_as_pdf_outlined,
                    label: _isRemove
                        ? 'Chọn PDF cần xóa trang'
                        : 'Chọn PDF cần trích trang',
                    picked: _input == null ? null : fileBaseName(_input!.path),
                    onPick: _pick,
                    trailing: hasPages
                        ? Chip(label: Text('$_pageCount trang'))
                        : null,
                  ),
                  if (_opening) ...[
                    const SizedBox(height: 8),
                    const RunningPane(message: 'Đang mở file…'),
                  ],
                  if (hasPages) ...[
                    const SizedBox(height: 12),
                    Text(
                      _isRemove
                          ? 'Chạm vào trang muốn xóa'
                          : 'Chạm vào trang muốn lấy ra thành file mới',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _running || _selected.length == _pageCount
                              ? null
                              : _selectAll,
                          icon: const Icon(Icons.select_all_rounded),
                          label: const Text('Chọn tất cả'),
                        ),
                        TextButton.icon(
                          onPressed: _running || _selected.isEmpty
                              ? null
                              : _clearSelection,
                          icon: const Icon(Icons.deselect_rounded),
                          label: const Text('Bỏ chọn'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (hasPages)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Lazy, so only the visible thumbnails are decoded.
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _tileExtent,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: _tileAspect,
                ),
                itemCount: _pageCount,
                itemBuilder: (context, i) => _PageTile(
                  number: i + 1,
                  thumb: _thumbs[i],
                  selected: _selected.contains(i),
                  onTap: _running ? null : () => _toggle(i),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ErrorBanner(message: _error!),
                  if (_output != null)
                    ResultCard(file: _output!, extra: _outputNote),
                ],
              ),
            ),
          ),
        ],
      ),
      // Pinned below the grid, so a long file needs no scrolling to run.
      bottomNavigationBar: hasPages ? _actionBar(theme) : null,
    );
  }

  Widget _actionBar(ThemeData theme) {
    final scheme = theme.colorScheme;
    final count = _selected.length;
    final verb = _isRemove ? 'Xóa' : 'Lấy';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_removesAll) ...[
                Text(
                  'Không thể xóa hết mọi trang. Hãy bỏ chọn ít nhất 1 trang.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_running)
                RunningPane(
                  message: _isRemove ? 'Đang xóa trang…' : 'Đang lấy trang…',
                )
              else
                RunButton(
                  label: count == 0 ? '$verb trang' : '$verb $count trang',
                  enabled: count > 0 && !_removesAll,
                  onPressed: _run,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One page in the grid: its thumbnail, its number and a check when picked.
class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.number,
    required this.thumb,
    required this.selected,
    required this.onTap,
  });

  /// 1-based page number.
  final int number;
  final Uint8List? thumb;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Trang $number',
        child: Material(
          color: scheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: selected
                ? BorderSide(color: scheme.primary, width: 3)
                : BorderSide(color: scheme.outlineVariant),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: thumb == null
                    ? Icon(Icons.description_outlined, color: scheme.outline)
                    : Image.memory(
                        thumb!,
                        fit: BoxFit.contain,
                        // Decodes no larger than the thumbnail is meant to
                        // be, even if a page renders bigger.
                        cacheWidth: _thumbWidth,
                        excludeFromSemantics: true,
                      ),
              ),
              if (selected)
                ColoredBox(color: scheme.primary.withValues(alpha: 0.12)),
              ExcludeSemantics(
                // Small badges on a small tile: cap their growth so they
                // never cover the page at the largest text sizes.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.5,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _CheckBadge(selected: selected),
                      ),
                      Positioned(
                        left: 4,
                        right: 4,
                        bottom: 6,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.inverseSurface.withValues(
                                alpha: 0.85,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              child: Text(
                                '$number',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onInverseSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // On top of the thumbnail, so the ripple shows over the page.
              Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap, child: const SizedBox.expand()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A filled circle with a check when [selected], an empty ring otherwise.
class _CheckBadge extends StatelessWidget {
  const _CheckBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? scheme.primary
            : scheme.surface.withValues(alpha: 0.9),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 18, color: scheme.onPrimary)
          : null,
    );
  }
}
