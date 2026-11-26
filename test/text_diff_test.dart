import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_utils/text_diff.dart';

const _eq = DiffType.equal;
const _ins = DiffType.insert;
const _del = DiffType.delete;

/// The old and the new text, rebuilt from [chunks].
(String, String) _sides(List<DiffChunk> chunks) => (
  [
    for (final c in chunks)
      if (c.type != _ins) c.text,
  ].join(' '),
  [
    for (final c in chunks)
      if (c.type != _del) c.text,
  ].join(' '),
);

String _normalized(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

int _changedWords(List<DiffChunk> chunks) => chunks
    .where((c) => c.type != _eq)
    .fold(0, (n, c) => n + c.text.split(' ').length);

/// Checks that [chunks] rebuild both texts, never repeat a type back to
/// back, and put a deletion before the insertion it pairs with.
void _expectValid(List<DiffChunk> chunks, String oldText, String newText) {
  final (old, neu) = _sides(chunks);
  expect(old, _normalized(oldText));
  expect(neu, _normalized(newText));
  for (var k = 0; k < chunks.length; k++) {
    expect(chunks[k].text, isNotEmpty);
    if (k == 0) continue;
    final prev = chunks[k - 1].type;
    final cur = chunks[k].type;
    expect(prev, isNot(cur), reason: 'chunks $k-1 and $k share a type');
    expect(
      prev == _ins && cur == _del,
      isFalse,
      reason: 'insert before delete',
    );
  }
}

/// Length of the longest common subsequence, by dynamic programming.
int _lcs(List<String> a, List<String> b) {
  var prev = List.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final cur = List.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] == b[j - 1]
          ? prev[j - 1] + 1
          : max(prev[j], cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Seeded random words from a skewed vocabulary, so common words repeat the
/// way function words do in prose.
List<String> _randomWords(Random random, int count, {int vocabulary = 3000}) =>
    [
      for (var i = 0; i < count; i++)
        'w${(pow(random.nextDouble(), 3) * vocabulary).floor()}',
    ];

/// [words] with about [rate] of the positions replaced, deleted or followed
/// by inserted words.
List<String> _edit(Random random, List<String> words, double rate) {
  final out = <String>[];
  for (final w in words) {
    if (random.nextDouble() >= rate) {
      out.add(w);
      continue;
    }
    switch (random.nextInt(3)) {
      case 0:
        out.add('new${random.nextInt(1 << 20)}');
      case 1:
        break;
      default:
        out.add(w);
        for (var k = random.nextInt(3); k >= 0; k--) {
          out.add('ins${random.nextInt(99)}');
        }
    }
  }
  return out;
}

/// Joins [words] with spaces and, now and then, line breaks.
String _wrap(Random random, List<String> words) {
  final buffer = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    if (i > 0) buffer.write(random.nextInt(12) == 0 ? '\n' : ' ');
    buffer.write(words[i]);
  }
  return buffer.toString();
}

/// "w1 w2 … wN" with the given words swapped for "X".
String _numbered(int count, {Set<int> replaced = const {}}) =>
    [for (var i = 1; i <= count; i++) replaced.contains(i) ? 'X' : 'w$i']
        .join(' ');

void main() {
  group('diffWords', () {
    test('text that only wraps differently is equal', () {
      expect(
        diffWords(
          'Hợp đồng  này\ncó hiệu lực\r\n',
          ' Hợp đồng này có\thiệu\nlực',
        ),
        [const DiffChunk(_eq, 'Hợp đồng này có hiệu lực')],
      );
    });

    test('empty or blank texts give no chunks', () {
      expect(diffWords('', ''), isEmpty);
      expect(diffWords(' \n ', '\t'), isEmpty);
    });

    test('one empty side is a single insert or delete', () {
      expect(diffWords('', 'một hai'), [const DiffChunk(_ins, 'một hai')]);
      expect(diffWords('một hai', '  '), [const DiffChunk(_del, 'một hai')]);
    });

    test('a replaced word is a delete followed by an insert', () {
      expect(diffWords('a b c', 'a x c'), [
        const DiffChunk(_eq, 'a'),
        const DiffChunk(_del, 'b'),
        const DiffChunk(_ins, 'x'),
        const DiffChunk(_eq, 'c'),
      ]);
    });

    test('edits at the very start and end', () {
      expect(diffWords('a b c d', 'x b c d y'), [
        const DiffChunk(_del, 'a'),
        const DiffChunk(_ins, 'x'),
        const DiffChunk(_eq, 'b c d'),
        const DiffChunk(_ins, 'y'),
      ]);
    });

    test('Vietnamese edits keep the unchanged words between them', () {
      expect(
        diffWords(
          'Hợp đồng có hiệu lực từ ngày 01/01/2026.',
          'Hợp đồng này có hiệu lực kể từ ngày 15/02/2026.',
        ),
        [
          const DiffChunk(_eq, 'Hợp đồng'),
          const DiffChunk(_ins, 'này'),
          const DiffChunk(_eq, 'có hiệu lực'),
          const DiffChunk(_ins, 'kể'),
          const DiffChunk(_eq, 'từ ngày'),
          const DiffChunk(_del, '01/01/2026.'),
          const DiffChunk(_ins, '15/02/2026.'),
        ],
      );
    });

    test('soft hyphens and zero-width spaces do not count', () {
      expect(
        diffWords(
          'Tài liệu docu\u00ADment\u200Bation sẵn sàng',
          'Tài liệu documentation sẵn sàng',
        ),
        [const DiffChunk(_eq, 'Tài liệu documentation sẵn sàng')],
      );
    });

    test('cleanup folds a chance match into the surrounding change', () {
      const old = 'alpha beta gamma và delta epsilon zeta';
      const neu = 'one two three và four five six';
      expect(diffWords(old, neu, cleanup: false), [
        const DiffChunk(_del, 'alpha beta gamma'),
        const DiffChunk(_ins, 'one two three'),
        const DiffChunk(_eq, 'và'),
        const DiffChunk(_del, 'delta epsilon zeta'),
        const DiffChunk(_ins, 'four five six'),
      ]);
      expect(diffWords(old, neu), [
        const DiffChunk(_del, old),
        const DiffChunk(_ins, neu),
      ]);
    });

    test('random edits: valid, and minimal without cleanup', () {
      final random = Random(1);
      for (var round = 0; round < 400; round++) {
        final old = _randomWords(random, random.nextInt(40), vocabulary: 8);
        final neu = random.nextBool()
            ? _edit(random, old, 0.3)
            : _randomWords(random, random.nextInt(40), vocabulary: 8);
        final oldText = _wrap(random, old);
        final newText = _wrap(random, neu);

        final raw = diffWords(oldText, newText, cleanup: false);
        _expectValid(raw, oldText, newText);
        expect(
          _changedWords(raw),
          old.length + neu.length - 2 * _lcs(old, neu),
          reason: 'round $round: $old → $neu',
        );

        final cleaned = diffWords(oldText, newText);
        _expectValid(cleaned, oldText, newText);
        expect(
          _changedWords(cleaned),
          greaterThanOrEqualTo(_changedWords(raw)),
        );
      }
    });

    test('50k lightly edited words, wrapped differently, finish fast', () {
      final random = Random(7);
      final old = _randomWords(random, 50000);
      final oldText = _wrap(random, old);
      final newText = _wrap(random, _edit(random, old, 0.01));
      final watch = Stopwatch()..start();
      final chunks = diffWords(oldText, newText);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      _expectValid(chunks, oldText, newText);
      // About 500 edits of one or two words each.
      expect(_changedWords(chunks), inInclusiveRange(400, 2000));
    });

    test('50k heavily edited or unrelated words stay fast and valid', () {
      // Both go past the cost cap, so they also check the approximate split.
      final random = Random(9);
      final old = _randomWords(random, 50000);
      for (final neu in [
        _edit(random, old, 0.15),
        _randomWords(random, 50000),
      ]) {
        final oldText = old.join(' ');
        final newText = neu.join(' ');
        final watch = Stopwatch()..start();
        final chunks = diffWords(oldText, newText);
        watch.stop();
        expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
        _expectValid(chunks, oldText, newText);
      }
    });
  });

  group('changedRegions', () {
    test('identical texts have no regions', () {
      expect(changedRegions(diffWords('a b c', 'a  b\nc')), isEmpty);
      expect(changedRegions(const []), isEmpty);
    });

    test('keeps 8 words of context on each side', () {
      final regions = changedRegions(
        diffWords(_numbered(30), _numbered(30, replaced: {15})),
      );
      expect(regions, hasLength(1));
      expect(regions.single.clippedStart, isTrue);
      expect(regions.single.clippedEnd, isTrue);
      expect(regions.single.chunks, [
        const DiffChunk(_eq, 'w7 w8 w9 w10 w11 w12 w13 w14'),
        const DiffChunk(_del, 'w15'),
        const DiffChunk(_ins, 'X'),
        const DiffChunk(_eq, 'w16 w17 w18 w19 w20 w21 w22 w23'),
      ]);
    });

    test('merges close changes and splits distant ones', () {
      final close = changedRegions(
        diffWords(_numbered(30), _numbered(30, replaced: {10, 20})),
      );
      expect(close, hasLength(1));
      expect(close.single.chunks.map((c) => c.type), [
        _eq,
        _del,
        _ins,
        _eq,
        _del,
        _ins,
        _eq,
      ]);
      expect(
        close.single.chunks[3].text,
        'w11 w12 w13 w14 w15 w16 w17 w18 w19',
      );

      final far = changedRegions(
        diffWords(_numbered(60), _numbered(60, replaced: {5, 40})),
      );
      expect(far, hasLength(2));
      expect(far[0].clippedStart, isFalse);
      expect(far[0].chunks.first, const DiffChunk(_eq, 'w1 w2 w3 w4'));
      expect(far[0].clippedEnd, isTrue);
      expect(far[0].chunks.last.text, 'w6 w7 w8 w9 w10 w11 w12 w13');
      expect(far[1].clippedStart, isTrue);
      expect(far[1].chunks.first.text, 'w32 w33 w34 w35 w36 w37 w38 w39');
      expect(far[1].clippedEnd, isTrue);
    });

    test('changes at the edges have no context to clip', () {
      final regions = changedRegions(diffWords('a b c', 'x b c y'));
      expect(regions, hasLength(1));
      expect(regions.single.clippedStart, isFalse);
      expect(regions.single.clippedEnd, isFalse);
      expect(regions.single.chunks, [
        const DiffChunk(_del, 'a'),
        const DiffChunk(_ins, 'x'),
        const DiffChunk(_eq, 'b c'),
        const DiffChunk(_ins, 'y'),
      ]);
    });
  });
}
