/// Extractive summary of a text: the sentences that share the most words
/// with the rest of it, ranked with TextRank.
///
/// Pure Dart (no Flutter imports), so it runs inside `Isolate.run` and in
/// plain unit tests. Deterministic: the same text always gives the same
/// summary.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'diacritics.dart';

/// Shorter sentences are headings, labels or page numbers.
const _minWords = 5;

/// TextRank compares every pair of sentences, so longer texts are narrowed
/// to this many candidates first.
const _maxCandidates = 500;

const _damping = 0.85;
const _iterations = 30;

/// Picks up to [maxSentences] key sentences of [text], in their original
/// order.
///
/// Sentences under five words never count. When no more than
/// [maxSentences] sentences qualify, all of them come back. Lines repeated
/// on three or more pages (running headers and footers) are skipped, and a
/// sentence that appears twice counts once.
List<String> summarize(String text, {int maxSentences = 7}) {
  if (maxSentences < 1) return const [];
  var pool = _candidates(splitSentences(text));
  if (pool.length <= maxSentences) return [for (final s in pool) s.text];
  if (pool.length > _maxCandidates) {
    pool = _mostConnected(pool, _maxCandidates);
  }
  return [for (final i in _top(_textRank(pool), maxSentences)) pool[i].text];
}

/// Splits [text] into sentences, with whitespace collapsed and list bullets
/// removed.
///
/// PDF text breaks lines wherever the page ran out of width, so a line break
/// ends a sentence only when the next line can't continue it: after a blank
/// line, before a list item, or before a line starting with a capital when
/// the previous line stopped short (a heading or paragraph end) or ended in
/// something other than a lowercase letter or a comma. Inside those blocks a
/// sentence ends at `.`, `!`, `?`, `…` or `;` followed by a space and
/// anything but a lowercase letter, except after an abbreviation such as
/// "TP." or "Mr.".
List<String> splitSentences(String text) {
  final sentences = <String>[];
  // Composed form, so the same word typed two ways counts as one word.
  for (final block in _blocks(composeVietnamese(text))) {
    _splitBlock(block, sentences);
  }
  return sentences;
}

class _Sentence {
  _Sentence(this.text, this.wordCount, this.words);

  final String text;

  /// Every word, for the length term of the similarity.
  final int wordCount;

  /// Distinct lowercased words without stop words, for the shared count.
  final Set<String> words;
}

final _word = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);
final _digit = RegExp(r'\d');

List<_Sentence> _candidates(List<String> sentences) {
  final parsed = <({String key, _Sentence sentence})>[];
  final counts = <String, int>{};
  for (final text in sentences) {
    final tokens = [
      for (final m in _word.allMatches(text.toLowerCase())) m[0]!,
    ];
    if (tokens.length < _minWords) continue;
    // Copies of a running header or footer differ only in page numbers and
    // are line fragments; full sentences that differ only in numbers ("Doanh
    // thu quý 1 tăng 5%.", "… quý 2 …") are separate facts.
    final key = _endsWithPunctuation(text)
        ? tokens.join(' ')
        : tokens.where((t) => !t.contains(_digit)).join(' ');
    counts[key] = (counts[key] ?? 0) + 1;
    final words = {
      for (final t in tokens)
        if (!_stopWords.contains(t)) t,
    };
    parsed.add((key: key, sentence: _Sentence(text, tokens.length, words)));
  }
  final kept = <String>{};
  final candidates = <_Sentence>[];
  for (final p in parsed) {
    if (counts[p.key]! >= 3 || !kept.add(p.key)) continue;
    candidates.add(p.sentence);
  }
  return candidates;
}

/// The [limit] sentences sharing the most words with the others, in their
/// original order: one cheap step of TextRank, used to narrow long texts.
List<_Sentence> _mostConnected(List<_Sentence> all, int limit) {
  final frequency = <String, int>{};
  var meanLog = 0.0;
  for (final s in all) {
    for (final w in s.words) {
      frequency[w] = (frequency[w] ?? 0) + 1;
    }
    meanLog += math.log(s.wordCount);
  }
  meanLog /= all.length;
  final scores = [
    for (final s in all)
      s.words.fold(0, (n, w) => n + frequency[w]! - 1) /
          (math.log(s.wordCount) + meanLog),
  ];
  return [for (final i in _top(scores, limit)) all[i]];
}

/// TextRank (Mihalcea & Tarau, 2004): a sentence ranks high when
/// high-ranking sentences share words with it. Two sentences are linked by
/// their shared words divided by the sum of their log lengths.
Float64List _textRank(List<_Sentence> sentences) {
  final n = sentences.length;
  final logLength = [for (final s in sentences) math.log(s.wordCount)];
  final weight = Float64List(n * n);
  final total = Float64List(n);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final shared = _sharedCount(sentences[i].words, sentences[j].words);
      if (shared == 0) continue;
      final w = shared / (logLength[i] + logLength[j]);
      weight[i * n + j] = w;
      weight[j * n + i] = w;
      total[i] += w;
      total[j] += w;
    }
  }
  var score = Float64List(n)..fillRange(0, n, 1);
  for (var round = 0; round < _iterations; round++) {
    final next = Float64List(n);
    for (var j = 0; j < n; j++) {
      if (total[j] == 0) continue;
      final share = score[j] / total[j];
      final row = j * n;
      for (var i = 0; i < n; i++) {
        next[i] += weight[row + i] * share;
      }
    }
    for (var i = 0; i < n; i++) {
      next[i] = (1 - _damping) + _damping * next[i];
    }
    score = next;
  }
  return score;
}

int _sharedCount(Set<String> a, Set<String> b) {
  final (small, large) = a.length <= b.length ? (a, b) : (b, a);
  var shared = 0;
  for (final w in small) {
    if (large.contains(w)) shared++;
  }
  return shared;
}

/// Indexes of the [count] highest [scores] (earlier wins a tie), ascending.
List<int> _top(List<double> scores, int count) {
  final order = List<int>.generate(scores.length, (i) => i)
    ..sort((p, q) {
      final byScore = scores[q].compareTo(scores[p]);
      return byScore != 0 ? byScore : p.compareTo(q);
    });
  return order.take(count).toList()..sort();
}

// ── Sentence splitting ──

final _lineBreak = RegExp(r'\r\n?|[\n\f\u2028\u2029]');
final _spaces = RegExp(r'\s+');

/// A line that starts a list item: a bullet, or "1." / "2)" / "a)" + space.
final _listItem = RegExp(
  r'^(?:[•·▪►●○◦]|[-–—*+]\s|\d{1,3}[.)]\s|[A-Za-z][.)]\s)',
);

/// Bullets to drop from the start of a sentence; dashes and plus signs only
/// when a space follows, so "-5%" and "+84" stay.
final _leadingBullet = RegExp(r'^(?:[•·▪►●○◦]\s*|[-–—*+]+\s+)');

/// Sentence-ending punctuation: . ! ? … ;
const _terminators = {0x2E, 0x21, 0x3F, 0x2026, 0x3B};

/// Closing quotes and brackets that may follow the punctuation.
const _closers = {0x22, 0x27, 0x201D, 0x2019, 0xBB, 0x29, 0x5D};

/// Abbreviations a "." doesn't end a sentence after (compared lowercased).
/// Single capitals are not treated as initials, because contracts end
/// sentences with "Bên A."; nor are "no"/"co", which are Vietnamese words.
const _abbreviations = {
  'tp', 'tx', 'p', 'q', 'ts', 'ths', 'pgs', 'gs', 'bs', 'ks', 'vd', 'tr', //
  'nxb', 'mr', 'mrs', 'ms', 'dr', 'prof', 'st', 'ltd', 'inc', 'jr', 'sr',
  'vs', 'fig',
};

/// Joins wrapped lines into blocks that hold one or more whole sentences.
List<String> _blocks(String text) {
  final lines = [
    for (final raw in text.split(_lineBreak))
      raw.replaceAll(_spaces, ' ').trim(),
  ];
  final fullWidth = _fullLineLength(lines);
  final blocks = <String>[];
  final current = StringBuffer();
  var previous = '';
  for (final line in lines) {
    if (line.isNotEmpty &&
        current.isNotEmpty &&
        _continues(previous, line, fullWidth)) {
      current
        ..write(' ')
        ..write(line);
    } else {
      if (current.isNotEmpty) blocks.add(current.toString());
      current
        ..clear()
        ..write(line);
    }
    previous = line;
  }
  if (current.isNotEmpty) blocks.add(current.toString());
  return blocks;
}

/// Length of a line that fills the text width: the 95th percentile of the
/// non-empty line lengths (the longest line in short texts), so a few odd
/// long lines don't count while lists and headings can't pull it down.
int _fullLineLength(List<String> lines) {
  final lengths = [
    for (final l in lines)
      if (l.isNotEmpty) l.length,
  ]..sort();
  if (lengths.isEmpty) return 0;
  return lengths[math.min(lengths.length - 1, lengths.length * 19 ~/ 20)];
}

/// Whether [line] carries on the sentence of the [previous] line.
bool _continues(String previous, String line, int fullWidth) {
  if (_listItem.hasMatch(line)) return false;
  if (_isLower(line[0])) return true;
  // A line that stops well short of the width ends a paragraph or is a
  // heading, even without punctuation.
  if (previous.length < fullWidth * 0.6) return false;
  final last = previous[previous.length - 1];
  return last == ',' || _isLower(last);
}

void _splitBlock(String block, List<String> out) {
  var start = 0;
  var i = 0;
  while (i < block.length) {
    if (!_terminators.contains(block.codeUnitAt(i))) {
      i++;
      continue;
    }
    var end = i + 1;
    while (end < block.length && _terminators.contains(block.codeUnitAt(end))) {
      end++;
    }
    final loneDot = end == i + 1 && block.codeUnitAt(i) == 0x2E;
    while (end < block.length && _closers.contains(block.codeUnitAt(end))) {
      end++;
    }
    // Blocks hold single spaces only: a boundary is punctuation, one space,
    // then the next sentence.
    if (end + 1 < block.length &&
        block.codeUnitAt(end) == 0x20 &&
        !_isLower(block[end + 1]) &&
        !(loneDot && _isAbbreviation(block, i))) {
      _addSentence(block.substring(start, end), out);
      start = end + 1;
    }
    i = end;
  }
  _addSentence(block.substring(start), out);
}

bool _endsWithPunctuation(String sentence) {
  var i = sentence.length - 1;
  while (i >= 0 && _closers.contains(sentence.codeUnitAt(i))) {
    i--;
  }
  return i >= 0 && _terminators.contains(sentence.codeUnitAt(i));
}

void _addSentence(String sentence, List<String> out) {
  final s = sentence.replaceFirst(_leadingBullet, '').trim();
  if (s.isNotEmpty) out.add(s);
}

/// Whether the word before the "." at [dot] is one of [_abbreviations].
bool _isAbbreviation(String block, int dot) {
  var start = dot;
  while (start > 0 && _isLetter(block[start - 1])) {
    start--;
  }
  return _abbreviations.contains(block.substring(start, dot).toLowerCase());
}

bool _isLower(String ch) => ch != ch.toUpperCase();

bool _isLetter(String ch) => ch.toLowerCase() != ch.toUpperCase();

/// Words too common to tell sentences apart: Vietnamese syllables and
/// English words. English "an", "in", "to", "no", "so", "may", "am" are left
/// out because they are also Vietnamese syllables ("an toàn", "máy in").
const _stopWords = {
  // Vietnamese
  'và', 'của', 'là', 'có', 'được', 'cho', 'các', 'những', 'một', 'trong', //
  'với', 'này', 'đó', 'đã', 'sẽ', 'đang', 'không', 'thì', 'mà', 'như',
  'khi', 'để', 'từ', 'theo', 'về', 'tại', 'trên', 'ra', 'vào', 'cũng',
  'nhưng', 'hay', 'hoặc', 'nếu', 'vì', 'do', 'bởi', 'nên', 'rằng', 'thể',
  'việc', 'sự', 'rất', 'còn', 'lại', 'chỉ', 'đến', 'bị', 'nào', 'gì', 'ấy',
  'đây', 'vẫn', 'đều', 'mỗi', 'cả', 'qua', 'ở', 'bằng', 'cùng', 'nhau',
  'thế', 'vậy', 'hơn', 'nhất', 'ta', 'chúng', 'họ', 'tôi', 'mình', 'nhiều',
  'ít', 'nữa', 'luôn', 'lên', 'sau', 'trước', 'giữa',
  // English
  'a', 'about', 'above', 'after', 'again', 'all', 'also', 'and', 'any', //
  'are', 'as', 'at', 'be', 'because', 'been', 'before', 'being', 'between',
  'both', 'but', 'by', 'can', 'could', 'did', 'does', 'doing', 'down',
  'during', 'each', 'few', 'for', 'from', 'further', 'had', 'has', 'have',
  'having', 'he', 'her', 'here', 'hers', 'him', 'his', 'how', 'i', 'if',
  'into', 'is', 'it', 'its', 'itself', 'just', 'me', 'more', 'most', 'my',
  'nor', 'not', 'now', 'of', 'off', 'on', 'once', 'only', 'or', 'other',
  'our', 'ours', 'out', 'over', 'own', 'same', 'shall', 'she', 'should',
  'some', 'such', 'than', 'that', 'the', 'their', 'theirs', 'them', 'then',
  'there', 'these', 'they', 'this', 'those', 'through', 'too', 'under',
  'until', 'up', 'upon', 'us', 'very', 'was', 'we', 'were', 'what', 'when',
  'where', 'which', 'while', 'who', 'whom', 'why', 'will', 'with', 'would',
  'you', 'your', 'yours',
};
