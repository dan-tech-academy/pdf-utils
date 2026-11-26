/// Word-level comparison of two texts.
///
/// Pure Dart (no Flutter imports), so it runs inside `Isolate.run` and in
/// plain unit tests.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'diacritics.dart';

/// What happened to a run of words on the way from the old text to the new.
enum DiffType { equal, insert, delete }

/// Consecutive words that share a [DiffType]. [text] holds the words
/// separated by single spaces.
class DiffChunk {
  const DiffChunk(this.type, this.text);

  final DiffType type;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffChunk && other.type == type && other.text == text;

  @override
  int get hashCode => Object.hash(type, text);

  @override
  String toString() => '${type.name}($text)';
}

/// Compares [oldText] with [newText] word by word.
///
/// Whitespace is normalised first: words are split on any run of spaces or
/// line breaks, so text that only wraps differently compares equal.
/// Invisible characters that PDFs leave inside words (soft hyphens,
/// zero-width spaces) are dropped. Each change is a [DiffType.delete] chunk
/// followed by a [DiffType.insert] chunk; either may be missing.
///
/// With [cleanup] (the default), a few unchanged words caught between larger
/// changes are folded into them, so a rewritten passage reads as one change
/// instead of a patchwork around chance matches such as "và" or "the".
///
/// Costs O((N + M) · D) for N and M words with D of them changed. A cost cap
/// keeps very different texts near-linear; past it the result is still a
/// correct diff, just not always the smallest one.
List<DiffChunk> diffWords(
  String oldText,
  String newText, {
  bool cleanup = true,
}) {
  // Composed form, so the same word typed two ways doesn't count as changed.
  final a = _words(composeVietnamese(oldText));
  final b = _words(composeVietnamese(newText));
  // Compare small ints instead of strings in the hot loops.
  final ids = <String, int>{};
  final x = Int32List(a.length);
  for (var i = 0; i < a.length; i++) {
    x[i] = ids.putIfAbsent(a[i], () => ids.length);
  }
  final y = Int32List(b.length);
  for (var j = 0; j < b.length; j++) {
    y[j] = ids.putIfAbsent(b[j], () => ids.length);
  }
  final deleted = Uint8List(a.length);
  final inserted = Uint8List(b.length);
  _Myers(x, y, deleted, inserted).compare(0, a.length, 0, b.length, false);
  if (cleanup) _absorbSmallEqualities(a, b, deleted, inserted);
  return _chunks(a, b, deleted, inserted);
}

/// A stretch of changes with a little unchanged text around it.
///
/// [clippedStart] and [clippedEnd] say whether unchanged words were left out
/// before the first chunk or after the last one.
class DiffRegion {
  const DiffRegion(
    this.chunks, {
    required this.clippedStart,
    required this.clippedEnd,
  });

  final List<DiffChunk> chunks;
  final bool clippedStart;
  final bool clippedEnd;
}

/// Groups the changes in [chunks] (from [diffWords]) into regions, keeping
/// at most [context] unchanged words on each side of a change.
///
/// Changes separated by no more than `2 * context` unchanged words share a
/// region. Identical texts give no regions.
List<DiffRegion> changedRegions(List<DiffChunk> chunks, {int context = 8}) {
  assert(context >= 0, 'context must not be negative');
  final regions = <DiffRegion>[];
  var current = <DiffChunk>[];
  var clippedStart = false;
  void addEqual(List<String> words) {
    if (words.isEmpty) return;
    current.add(DiffChunk(DiffType.equal, words.join(' ')));
  }

  for (var k = 0; k < chunks.length; k++) {
    final chunk = chunks[k];
    if (chunk.type != DiffType.equal) {
      current.add(chunk);
      continue;
    }
    final first = k == 0;
    final last = k == chunks.length - 1;
    if (first && last) break;
    final words = chunk.text.split(' ');
    if (first) {
      clippedStart = words.length > context;
      addEqual(clippedStart ? words.sublist(words.length - context) : words);
    } else if (last) {
      final clipped = words.length > context;
      addEqual(clipped ? words.sublist(0, context) : words);
      regions.add(
        DiffRegion(current, clippedStart: clippedStart, clippedEnd: clipped),
      );
      current = [];
    } else if (words.length <= 2 * context) {
      current.add(chunk);
    } else {
      addEqual(words.sublist(0, context));
      regions.add(
        DiffRegion(current, clippedStart: clippedStart, clippedEnd: true),
      );
      current = [];
      clippedStart = true;
      addEqual(words.sublist(words.length - context));
    }
  }
  if (current.any((c) => c.type != DiffType.equal)) {
    regions.add(
      DiffRegion(current, clippedStart: clippedStart, clippedEnd: false),
    );
  }
  return regions;
}

final _whitespace = RegExp(r'\s+');

/// Soft hyphen, zero-width space/non-joiner/joiner, word joiner and BOM.
final _invisible = RegExp(r'[\u00AD\u200B-\u200D\u2060\uFEFF]');

List<String> _words(String text) => [
  for (final w in text.replaceAll(_invisible, '').split(_whitespace))
    if (w.isNotEmpty) w,
];

/// Turns the per-word marks into chunks, deletions before insertions.
List<DiffChunk> _chunks(
  List<String> a,
  List<String> b,
  Uint8List deleted,
  Uint8List inserted,
) {
  final chunks = <DiffChunk>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && deleted[i] == 1) {
      final start = i;
      while (i < a.length && deleted[i] == 1) {
        i++;
      }
      chunks.add(DiffChunk(DiffType.delete, a.sublist(start, i).join(' ')));
    } else if (j < b.length && inserted[j] == 1) {
      final start = j;
      while (j < b.length && inserted[j] == 1) {
        j++;
      }
      chunks.add(DiffChunk(DiffType.insert, b.sublist(start, j).join(' ')));
    } else {
      final start = i;
      while (i < a.length &&
          j < b.length &&
          deleted[i] == 0 &&
          inserted[j] == 0) {
        i++;
        j++;
      }
      // Unmarked words always pair up; anything else is a bug, and looping
      // on would never end.
      if (i == start) throw StateError('Diff marks are out of step');
      chunks.add(DiffChunk(DiffType.equal, a.sublist(start, i).join(' ')));
    }
  }
  return chunks;
}

/// A change: old words `[a0, a1)` replaced by new words `[b0, b1)`.
typedef _Change = ({int a0, int a1, int b0, int b1});

/// Folds each unchanged stretch into the changes around it when the stretch
/// is no longer than the larger side of the change before it and of the
/// change after it. Lengths count characters, so short function words are
/// absorbed and real anchors (names, numbers with context) are kept. This is
/// the equality rule of diff-match-patch's semantic cleanup.
void _absorbSmallEqualities(
  List<String> a,
  List<String> b,
  Uint8List deleted,
  Uint8List inserted,
) {
  // Prefix sums of word lengths (plus one for the following space).
  final wa = Int32List(a.length + 1);
  for (var i = 0; i < a.length; i++) {
    wa[i + 1] = wa[i] + a[i].length + 1;
  }
  final wb = Int32List(b.length + 1);
  for (var j = 0; j < b.length; j++) {
    wb[j + 1] = wb[j] + b[j].length + 1;
  }
  int side(_Change c) => math.max(wa[c.a1] - wa[c.a0], wb[c.b1] - wb[c.b0]);

  // Merging a change into the previous one can let that one absorb the
  // stretch before it in turn, so finished changes wait on a stack.
  final stack = <_Change>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    final isDeleted = i < a.length && deleted[i] == 1;
    final isInserted = j < b.length && inserted[j] == 1;
    if (!isDeleted && !isInserted) {
      i++;
      j++;
      continue;
    }
    final a0 = i;
    final b0 = j;
    while (i < a.length && deleted[i] == 1) {
      i++;
    }
    while (j < b.length && inserted[j] == 1) {
      j++;
    }
    var change = (a0: a0, a1: i, b0: b0, b1: j);
    while (stack.isNotEmpty) {
      final prev = stack.last;
      final gap = wa[change.a0] - wa[prev.a1];
      if (gap > side(prev) || gap > side(change)) break;
      stack.removeLast();
      change = (a0: prev.a0, a1: change.a1, b0: prev.b0, b1: change.b1);
    }
    stack.add(change);
  }
  for (final c in stack) {
    deleted.fillRange(c.a0, c.a1, 1);
    inserted.fillRange(c.b0, c.b1, 1);
  }
}

/// A search never settles for an approximate split before this many edit
/// steps. Higher finds smaller diffs for heavily edited texts but costs
/// O((N + M) · limit) when the texts have little in common.
const _minCost = 1024;

/// Sentinel above any word index.
const _maxIndex = 0x7fffffff;

/// Myers' O(ND) difference algorithm in linear space, after GNU diff's
/// `diffseq.h`. Marks the words of [x] that were [deleted] and the words of
/// [y] that were [inserted].
class _Myers {
  _Myers(this.x, this.y, this.deleted, this.inserted)
    : _offset = y.length + 1,
      _fd = Int32List(x.length + y.length + 3),
      _bd = Int32List(x.length + y.length + 3),
      _tooExpensive = _costLimit(x.length + y.length);

  final Int32List x;
  final Int32List y;
  final Uint8List deleted;
  final Uint8List inserted;

  /// Index of diagonal 0 (x - y == 0) in [_fd] and [_bd].
  final int _offset;

  /// Furthest x reached on each diagonal by the forward search.
  final Int32List _fd;

  /// Smallest x reached on each diagonal by the backward search.
  final Int32List _bd;

  /// Edit steps after which a search settles for its furthest point.
  final int _tooExpensive;

  /// About the square root of [total], and at least [_minCost].
  static int _costLimit(int total) {
    var limit = 1;
    for (var d = total + 3; d != 0; d >>= 2) {
      limit <<= 1;
    }
    return math.max(_minCost, limit);
  }

  /// Marks the changes between `x[xoff, xlim)` and `y[yoff, ylim)`.
  /// [minimal] forbids the approximate split for this range.
  void compare(int xoff, int xlim, int yoff, int ylim, bool minimal) {
    while (true) {
      while (xoff < xlim && yoff < ylim && x[xoff] == y[yoff]) {
        xoff++;
        yoff++;
      }
      while (xoff < xlim && yoff < ylim && x[xlim - 1] == y[ylim - 1]) {
        xlim--;
        ylim--;
      }
      if (xoff == xlim) {
        inserted.fillRange(yoff, ylim, 1);
        return;
      }
      if (yoff == ylim) {
        deleted.fillRange(xoff, xlim, 1);
        return;
      }
      final s = _split(xoff, xlim, yoff, ylim, minimal);
      // Recurse into the smaller half and loop on the larger one, so the
      // stack stays shallow even when approximate splits peel off small
      // pieces. Order doesn't matter: each half only sets its own marks.
      if ((s.x - xoff) + (s.y - yoff) <= (xlim - s.x) + (ylim - s.y)) {
        compare(xoff, s.x, yoff, s.y, s.loMinimal);
        xoff = s.x;
        yoff = s.y;
        minimal = s.hiMinimal;
      } else {
        compare(s.x, xlim, s.y, ylim, s.hiMinimal);
        xlim = s.x;
        ylim = s.y;
        minimal = s.loMinimal;
      }
    }
  }

  /// Finds where an optimal edit path crosses the middle of the range (the
  /// "middle snake"), searching from both corners at once. Past the cost
  /// limit, unless [minimal], it returns the point either search pushed
  /// furthest instead. Ranges must differ at both ends.
  ({int x, int y, bool loMinimal, bool hiMinimal}) _split(
    int xoff,
    int xlim,
    int yoff,
    int ylim,
    bool minimal,
  ) {
    final x = this.x;
    final y = this.y;
    final fd = _fd;
    final bd = _bd;
    final o = _offset;
    final dmin = xoff - ylim; // lowest diagonal in the range
    final dmax = xlim - yoff; // highest diagonal in the range
    final fmid = xoff - yoff; // where the forward search starts
    final bmid = xlim - ylim; // where the backward search starts
    var fmin = fmid;
    var fmax = fmid;
    var bmin = bmid;
    var bmax = bmid;
    // The searches can meet only after a forward step when the corners sit
    // on diagonals of different parity, and only after a backward one
    // otherwise.
    final odd = (fmid - bmid).isOdd;
    fd[o + fmid] = xoff;
    bd[o + bmid] = xlim;
    for (var cost = 1; ; cost++) {
      // One more edit step forward on every reachable diagonal.
      if (fmin > dmin) {
        fmin--;
        fd[o + fmin - 1] = -1;
      } else {
        fmin++;
      }
      if (fmax < dmax) {
        fmax++;
        fd[o + fmax + 1] = -1;
      } else {
        fmax--;
      }
      for (var d = fmax; d >= fmin; d -= 2) {
        final lo = fd[o + d - 1];
        final hi = fd[o + d + 1];
        final x0 = lo < hi ? hi : lo + 1;
        var xi = x0;
        var yi = x0 - d;
        while (xi < xlim && yi < ylim && x[xi] == y[yi]) {
          xi++;
          yi++;
        }
        fd[o + d] = xi;
        if (odd && bmin <= d && d <= bmax && bd[o + d] <= xi) {
          return (x: xi, y: yi, loMinimal: true, hiMinimal: true);
        }
      }

      // And one more step backward.
      if (bmin > dmin) {
        bmin--;
        bd[o + bmin - 1] = _maxIndex;
      } else {
        bmin++;
      }
      if (bmax < dmax) {
        bmax++;
        bd[o + bmax + 1] = _maxIndex;
      } else {
        bmax--;
      }
      for (var d = bmax; d >= bmin; d -= 2) {
        final lo = bd[o + d - 1];
        final hi = bd[o + d + 1];
        final x0 = lo < hi ? lo : hi - 1;
        var xi = x0;
        var yi = x0 - d;
        while (xi > xoff && yi > yoff && x[xi - 1] == y[yi - 1]) {
          xi--;
          yi--;
        }
        bd[o + d] = xi;
        if (!odd && fmin <= d && d <= fmax && xi <= fd[o + d]) {
          return (x: xi, y: yi, loMinimal: true, hiMinimal: true);
        }
      }

      if (minimal || cost < _tooExpensive) continue;

      // Too costly: split where one search got furthest. The part it
      // covered is optimal; the rest is searched again from there.
      var fxyBest = -1;
      var fxBest = 0;
      for (var d = fmax; d >= fmin; d -= 2) {
        var xi = math.min(fd[o + d], xlim);
        var yi = xi - d;
        if (ylim < yi) {
          xi = ylim + d;
          yi = ylim;
        }
        if (fxyBest < xi + yi) {
          fxyBest = xi + yi;
          fxBest = xi;
        }
      }
      var bxyBest = _maxIndex;
      var bxBest = 0;
      for (var d = bmax; d >= bmin; d -= 2) {
        var xi = math.max(xoff, bd[o + d]);
        var yi = xi - d;
        if (yi < yoff) {
          xi = yoff + d;
          yi = yoff;
        }
        if (xi + yi < bxyBest) {
          bxyBest = xi + yi;
          bxBest = xi;
        }
      }
      if ((xlim + ylim) - bxyBest < fxyBest - (xoff + yoff)) {
        return (
          x: fxBest,
          y: fxyBest - fxBest,
          loMinimal: true,
          hiMinimal: false,
        );
      }
      return (
        x: bxBest,
        y: bxyBest - bxBest,
        loMinimal: false,
        hiMinimal: true,
      );
    }
  }
}
