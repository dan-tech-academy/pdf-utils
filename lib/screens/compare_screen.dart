import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../errors.dart';
import '../files.dart';
import '../page_text.dart';
import '../pdf_ocr.dart';
import '../text_diff.dart';
import '../widgets.dart';

/// Compares the text of two PDFs word by word and shows only what changed.
/// A scanned version has its text recognized first.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

/// Changed regions drawn at most; the rest is only counted.
const _maxRegions = 300;

/// Words of one addition or deletion drawn before the rest is only counted.
const _maxChangeWords = 300;

/// What the background diff hands back to the screen.
class _Comparison {
  const _Comparison({
    required this.added,
    required this.removed,
    required this.regions,
    required this.totalRegions,
  });

  /// Places where words were added or removed.
  final int added;
  final int removed;

  /// The first [_maxRegions] changed regions.
  final List<DiffRegion> regions;
  final int totalRegions;
}

/// Diffs the two texts in a background isolate. Top-level, so the isolate
/// closure captures only the two strings.
Future<_Comparison> _compareInBackground(String oldText, String newText) =>
    Isolate.run(() {
      final chunks = diffWords(oldText, newText);
      final regions = changedRegions(chunks);
      return _Comparison(
        added: chunks.where((c) => c.type == DiffType.insert).length,
        removed: chunks.where((c) => c.type == DiffType.delete).length,
        regions: regions.length > _maxRegions
            ? regions.sublist(0, _maxRegions)
            : regions,
        totalRegions: regions.length,
      );
    });

/// One version's text, and whether it was recognized on a scan's pages.
typedef _VersionText = ({String text, bool scanned});

/// Why there is nothing to compare. [scanned]: an empty version was read as
/// a scan and no text was found on its pages either.
String _noTextMessage({
  required bool oldEmpty,
  required bool newEmpty,
  required bool scanned,
}) {
  final which = oldEmpty && newEmpty
      ? 'Cả hai file đều'
      : oldEmpty
      ? 'Bản cũ'
      : 'Bản mới';
  return scanned
      ? '$which không có chữ nào, kể cả khi đọc như bản scan. Có thể file '
            'chỉ có hình, hoặc chữ quá mờ.'
      : '$which không có chữ nào để so sánh.';
}

/// Warns that words recognized on a scan can be misread, and a misread word
/// shows as a change. Null when neither version is a scan.
String? _scanNote({required bool oldScanned, required bool newScanned}) {
  if (!oldScanned && !newScanned) return null;
  final which = oldScanned && newScanned
      ? 'Cả hai file đều'
      : oldScanned
      ? 'Bản cũ'
      : 'Bản mới';
  return '$which là bản scan nên chữ được nhận dạng tự động. Vài chỗ khác '
      'nhau có thể do đọc sai chữ.';
}

class _CompareScreenState extends State<CompareScreen> {
  File? _old;
  File? _new;

  /// Text of [_old] and [_new], kept so comparing again after picking the
  /// other version skips reading (and recognizing a scan) again.
  _VersionText? _oldText;
  _VersionText? _newText;
  bool _running = false;
  bool _cancelRequested = false;

  /// Progress while a version is read as a scan; null otherwise.
  String? _scanStatus;
  _Comparison? _result;

  /// Shown with [_result] when a version is a scan.
  String? _note;
  String? _error;

  /// True once the user pressed Hủy or left the screen.
  bool get _stopped => _cancelRequested || !mounted;

  Future<void> _pick({required bool old}) async {
    if (_running) return;
    try {
      final file = await pickPdfOrText();
      if (file == null || !mounted) return;
      setState(() {
        if (old) {
          _old = file;
          _oldText = null;
        } else {
          _new = file;
          _newText = null;
        }
        _result = null;
        _note = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Hủy is offered while a scan is recognized, and takes effect after the
  /// page being read.
  void _cancel() => setState(() {
    _cancelRequested = true;
    _scanStatus = 'Đang dừng…';
  });

  Future<void> _run() async {
    final oldFile = _old;
    final newFile = _new;
    if (oldFile == null || newFile == null || _running) return;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _scanStatus = null;
      _error = null;
      _result = null;
      _note = null;
    });
    // Names the file a read error belongs to.
    String? reading;
    try {
      reading = 'Bản cũ';
      final oldText = _oldText ??= await _read(oldFile, 'Bản cũ');
      if (oldText == null || _stopped) return;
      reading = 'Bản mới';
      final newText = _newText ??= await _read(newFile, 'Bản mới');
      if (newText == null || _stopped) return;
      reading = null;
      final oldEmpty = oldText.text.trim().isEmpty;
      final newEmpty = newText.text.trim().isEmpty;
      if (oldEmpty || newEmpty) {
        setState(
          () => _error = _noTextMessage(
            oldEmpty: oldEmpty,
            newEmpty: newEmpty,
            scanned:
                (oldEmpty && oldText.scanned) || (newEmpty && newText.scanned),
          ),
        );
        return;
      }
      final result = await _compareInBackground(oldText.text, newText.text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _note = _scanNote(
          oldScanned: oldText.scanned,
          newScanned: newText.scanned,
        );
      });
    } catch (e) {
      if (!mounted) return;
      final message = friendlyError(e);
      setState(() => _error = reading == null ? message : '$reading: $message');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _scanStatus = null;
        });
      }
    }
  }

  /// The text of [file], the version called [name], recognized on its pages
  /// when it is a scan. Null when the user cancelled meanwhile.
  Future<_VersionText?> _read(File file, String name) async {
    final read = await readOrRecognizePages(
      file,
      onScanProgress: (done, total) {
        if (!_stopped) {
          setState(() => _scanStatus = scanProgressText(name, done, total));
        }
      },
      isCancelled: () => _stopped,
    );
    if (read == null) return null;
    if (read.scanned && !_stopped) setState(() => _scanStatus = null);
    return (text: joinPages(read.pages), scanned: read.scanned);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('So sánh PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Chỉ so sánh phần chữ, không so sánh hình ảnh.', style: muted),
          const SizedBox(height: 12),
          PickTile(
            icon: Icons.history_rounded,
            label: 'Bản cũ',
            picked: _old == null ? null : fileBaseName(_old!.path),
            onPick: () => _pick(old: true),
          ),
          const SizedBox(height: 4),
          PickTile(
            icon: Icons.update_rounded,
            label: 'Bản mới',
            picked: _new == null ? null : fileBaseName(_new!.path),
            onPick: () => _pick(old: false),
          ),
          const SizedBox(height: 16),
          if (_running)
            RunningPane(
              message: _scanStatus ?? 'Đang so sánh…',
              onCancel: _scanStatus == null || _cancelRequested
                  ? null
                  : _cancel,
            )
          else
            RunButton(
              label: 'So sánh',
              enabled: _old != null && _new != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (result != null) ...[
            if (_note != null) ...[
              Text(_note!, style: muted),
              const SizedBox(height: 8),
            ],
            ..._resultViews(theme, result),
          ],
        ],
      ),
    );
  }

  /// The summary card, then one card per changed region. Spread straight
  /// into the list so off-screen regions are never laid out.
  List<Widget> _resultViews(ThemeData theme, _Comparison result) {
    final scheme = theme.colorScheme;
    if (result.added == 0 && result.removed == 0) {
      return const [
        _SummaryCard(
          icon: Icons.check_rounded,
          title: 'Hai file giống nhau về nội dung chữ.',
        ),
      ];
    }
    final _ChangeStyles styles = (
      insert: TextStyle(
        backgroundColor: scheme.primaryContainer,
        color: scheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
      delete: TextStyle(
        backgroundColor: scheme.errorContainer,
        color: scheme.onErrorContainer,
        decoration: TextDecoration.lineThrough,
        decorationColor: scheme.onErrorContainer,
      ),
      note: TextStyle(color: scheme.onSurfaceVariant),
    );
    final hidden = result.totalRegions - result.regions.length;
    return [
      _SummaryCard(
        icon: Icons.compare_arrows_rounded,
        title: 'Thêm ${result.added} chỗ · Xóa ${result.removed} chỗ',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Swatch(label: 'Chữ được thêm', style: styles.insert),
            _Swatch(label: 'Chữ bị xóa', style: styles.delete),
          ],
        ),
      ),
      for (final region in result.regions)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text.rich(_regionSpan(region, styles)),
          ),
        ),
      if (hidden > 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Chỉ hiện ${result.regions.length} đoạn đầu, còn $hidden đoạn có '
            'thay đổi nữa.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }
}

/// Text styles for added and removed words, and for the "… còn N chữ" note.
typedef _ChangeStyles = ({TextStyle insert, TextStyle delete, TextStyle note});

/// One region as running text: context plain, additions highlighted,
/// deletions struck through, "…" where unchanged text was left out.
TextSpan _regionSpan(DiffRegion region, _ChangeStyles styles) {
  final spans = <InlineSpan>[
    if (region.clippedStart) const TextSpan(text: '… '),
  ];
  for (var i = 0; i < region.chunks.length; i++) {
    if (i > 0) spans.add(const TextSpan(text: ' '));
    final chunk = region.chunks[i];
    switch (chunk.type) {
      case DiffType.equal:
        spans.add(TextSpan(text: chunk.text));
      case DiffType.insert:
        _addChange(spans, chunk.text, styles.insert, 'Thêm', styles.note);
      case DiffType.delete:
        _addChange(spans, chunk.text, styles.delete, 'Xóa', styles.note);
    }
  }
  if (region.clippedEnd) spans.add(const TextSpan(text: ' …'));
  return TextSpan(children: spans);
}

/// Adds a changed run, cut to [_maxChangeWords] words, labelled for screen
/// readers, which can't see the colours.
void _addChange(
  List<InlineSpan> spans,
  String text,
  TextStyle style,
  String label,
  TextStyle note,
) {
  final (shown, hidden) = _clipWords(text);
  spans.add(
    TextSpan(text: shown, style: style, semanticsLabel: '$label: $shown'),
  );
  if (hidden > 0) spans.add(TextSpan(text: ' … còn $hidden chữ', style: note));
}

/// The first [_maxChangeWords] words of [text] (single-spaced) and how many
/// words were cut.
(String, int) _clipWords(String text) {
  var spaces = 0;
  var cut = -1;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) != 0x20) continue;
    spaces++;
    if (spaces == _maxChangeWords) cut = i;
  }
  if (cut < 0) return (text, 0);
  return (text.substring(0, cut), spaces + 1 - _maxChangeWords);
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.icon, required this.title, this.child});

  final IconData icon;
  final String title;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTile(icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (child case final c?) ...[const SizedBox(height: 12), c],
          ],
        ),
      ),
    );
  }
}

/// A legend entry: [label] drawn the way the matching words are.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.merge(style),
        ),
      ),
    );
  }
}
