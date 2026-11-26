/// Page-level text helpers shared by the tools that read a document's text
/// (compare, summarize, translate).
library;

/// The line the app writes between pages in text it saves.
String pageMarker(int page) => '--- Trang $page ---';

final _marker = RegExp(
  r'^[ \t]*-{2,}[ \t]*Trang[ \t]+\d+[ \t]*-{2,}[ \t]*$',
  multiLine: true,
);

/// Splits text the app saved (OCR, translation) back into pages at its
/// [pageMarker] lines. Text without markers is a single page.
List<String> splitPageMarkers(String text) {
  final pages = [for (final p in text.split(_marker)) p.trim()];
  // Text that starts with a marker leaves an empty piece before it.
  if (pages.length > 1 && pages.first.isEmpty) pages.removeAt(0);
  return pages;
}

/// Lines at most this far from a page's top or bottom count as its header
/// or footer.
const _edge = 2;

/// Running headers and footers recur on at least this many pages.
const _minRepeats = 3;

/// Lines up to this long that hold a number ("Trang 3/10", "- 3 -") match
/// with the numbers ignored; longer ones must repeat word for word, so body
/// lines that differ only in numbers ("Điều 3. …") are kept.
const _maxNumberedLine = 40;

final _digits = RegExp(r'\d+');
final _spaces = RegExp(r'\s+');

/// The pages as one text, separated by a blank line, without running
/// headers and footers: a line among the first or last two of its page that
/// recurs there on three or more pages, word for word or, for a short line
/// with a page number, numbers aside. Pages too short to have both a header
/// or footer and a body are left whole.
///
/// The blank line between pages keeps a sentence from running on into the
/// next page's header.
String joinPages(List<String> pages) {
  final split = [for (final p in pages) p.split('\n')];

  Set<String> keys(String line) {
    final plain = line.trim().toLowerCase().replaceAll(_spaces, ' ');
    return {
      plain,
      if (plain.length <= _maxNumberedLine && _digits.hasMatch(plain))
        plain.replaceAll(_digits, '#'),
    };
  }

  List<int> edgeLines(List<String> lines) {
    final filled = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].trim().isNotEmpty) i,
    ];
    if (filled.length <= _edge * 2) return const [];
    return [...filled.take(_edge), ...filled.reversed.take(_edge)];
  }

  final counts = <String, int>{};
  for (final lines in split) {
    final seen = {for (final i in edgeLines(lines)) ...keys(lines[i])};
    for (final k in seen) {
      counts[k] = (counts[k] ?? 0) + 1;
    }
  }
  bool running(String line) =>
      keys(line).any((k) => (counts[k] ?? 0) >= _minRepeats);

  final out = <String>[];
  for (final lines in split) {
    final drop = {
      for (final i in edgeLines(lines))
        if (running(lines[i])) i,
    };
    final page = [
      for (var i = 0; i < lines.length; i++)
        if (!drop.contains(i)) lines[i],
    ].join('\n').trim();
    if (page.isNotEmpty) out.add(page);
  }
  return out.join('\n\n');
}
