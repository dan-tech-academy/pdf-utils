/// Folds Vietnamese letters to plain ASCII: "Hợp đồng" → "Hop dong".
///
/// Used for output file names (some share targets mangle non-ASCII names)
/// and for accent-insensitive search. Handles both precomposed text and the
/// decomposed form (base letter + combining marks) that iOS file names use.
String removeDiacritics(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    // Combining diacritical marks (U+0300–U+036F) left over from NFD text.
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final ch = String.fromCharCode(rune);
    out.write(_folded[ch] ?? ch);
  }
  return out.toString();
}

/// Vietnamese text in composed form: a base letter followed by combining
/// marks (as typed with a "Unicode tổ hợp" keyboard) becomes the single
/// precomposed letter, so "Hợp" matches however it was typed. Mark order
/// doesn't matter; combinations Vietnamese doesn't use are left as they are.
String composeVietnamese(String input) {
  final runes = input.runes.toList();
  if (!runes.any(_isMark)) return input;
  final out = StringBuffer();
  var i = 0;
  while (i < runes.length) {
    var end = i + 1;
    while (end < runes.length && _isMark(runes[end])) {
      end++;
    }
    final composed = end > i + 1
        ? _compose(runes[i], runes.sublist(i + 1, end))
        : null;
    if (composed != null) {
      out.write(composed);
      i = end;
    } else {
      out.writeCharCode(runes[i]);
      i++;
    }
  }
  return out.toString();
}

bool _isMark(int rune) => rune >= 0x0300 && rune <= 0x036F;

String? _compose(int base, List<int> marks) {
  final (letter, own) = _vietDecomposed[base] ?? (base, const <int>[]);
  final all = [...own, ...marks]..sort();
  return _vietComposed[String.fromCharCodes([letter, ...all])];
}

/// Each Vietnamese vowel family: its plain base letter, the mark that makes
/// the family (breve, circumflex, horn), and its six forms in tone order:
/// none, grave, acute, hook above, tilde, dot below.
const _vietFamilies = <(String, List<int>, String)>[
  ('a', [], 'aàáảãạ'),
  ('a', [0x306], 'ăằắẳẵặ'),
  ('a', [0x302], 'âầấẩẫậ'),
  ('e', [], 'eèéẻẽẹ'),
  ('e', [0x302], 'êềếểễệ'),
  ('i', [], 'iìíỉĩị'),
  ('o', [], 'oòóỏõọ'),
  ('o', [0x302], 'ôồốổỗộ'),
  ('o', [0x31B], 'ơờớởỡợ'),
  ('u', [], 'uùúủũụ'),
  ('u', [0x31B], 'ưừứửữự'),
  ('y', [], 'yỳýỷỹỵ'),
  ('A', [], 'AÀÁẢÃẠ'),
  ('A', [0x306], 'ĂẰẮẲẴẶ'),
  ('A', [0x302], 'ÂẦẤẨẪẬ'),
  ('E', [], 'EÈÉẺẼẸ'),
  ('E', [0x302], 'ÊỀẾỂỄỆ'),
  ('I', [], 'IÌÍỈĨỊ'),
  ('O', [], 'OÒÓỎÕỌ'),
  ('O', [0x302], 'ÔỒỐỔỖỘ'),
  ('O', [0x31B], 'ƠỜỚỞỠỢ'),
  ('U', [], 'UÙÚỦŨỤ'),
  ('U', [0x31B], 'ƯỪỨỬỮỰ'),
  ('Y', [], 'YỲÝỶỸỴ'),
];
const _tones = [0x300, 0x301, 0x309, 0x303, 0x323];

/// Precomposed letter → (base letter, its marks).
final Map<int, (int, List<int>)> _vietDecomposed = {
  for (final (base, marks, forms) in _vietFamilies)
    for (var t = 0; t < 6; t++)
      forms.codeUnitAt(t): (
        base.codeUnitAt(0),
        [...marks, if (t > 0) _tones[t - 1]],
      ),
};

/// Base letter + its marks in ascending order → precomposed letter.
final Map<String, String> _vietComposed = {
  for (final MapEntry(key: letter, value: (base, marks))
      in _vietDecomposed.entries)
    String.fromCharCodes([
      base,
      ...([...marks]..sort()),
    ]): String.fromCharCode(
      letter,
    ),
};

final Map<String, String> _folded = {
  for (final MapEntry(:key, :value) in const {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'A': 'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ',
    'e': 'èéẹẻẽêềếệểễ',
    'E': 'ÈÉẸẺẼÊỀẾỆỂỄ',
    'i': 'ìíịỉĩ',
    'I': 'ÌÍỊỈĨ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'O': 'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ',
    'u': 'ùúụủũưừứựửữ',
    'U': 'ÙÚỤỦŨƯỪỨỰỬỮ',
    'y': 'ỳýỵỷỹ',
    'Y': 'ỲÝỴỶỸ',
    'd': 'đ',
    'D': 'Đ',
  }.entries)
    for (final ch in value.split('')) ch: key,
};
