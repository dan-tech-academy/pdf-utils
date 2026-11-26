import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:share_plus/share_plus.dart';

import '../errors.dart';
import '../files.dart';
import '../page_text.dart';
import '../pdf_ocr.dart';
import '../widgets.dart';

/// Translates the text of a PDF (or an app-saved .txt) on the device with
/// ML Kit, page by page. A scanned PDF has its text recognized first. Each
/// language pack (about 30 MB) is downloaded once, on first use.
class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  /// Offered languages in menu order, each named by the word after "tiếng".
  static const _languages = {
    TranslateLanguage.vietnamese: 'Việt',
    TranslateLanguage.english: 'Anh',
    TranslateLanguage.chinese: 'Trung',
    TranslateLanguage.japanese: 'Nhật',
    TranslateLanguage.korean: 'Hàn',
  };

  /// A longer result shows only its start on screen, because laying out a
  /// whole book in one text widget stalls the UI. Copy, share and save
  /// always use the full text.
  static const _previewChars = 30000;

  /// A longer result is shared as a .txt file: Android refuses share
  /// intents larger than about 1 MB.
  static const _maxShareChars = 50000;

  /// Language-pack downloads in progress. A download can't be stopped, so
  /// after Hủy it carries on, and the next run waits for it again instead
  /// of starting a second one (which iOS refuses).
  static final _downloads = <TranslateLanguage, Future<bool>>{};

  File? _input;

  /// Text of [_input], kept so translating into another language skips the
  /// reading (and a scan's recognition).
  DocumentPages? _source;
  TranslateLanguage _from = TranslateLanguage.english;
  TranslateLanguage _to = TranslateLanguage.vietnamese;
  bool _running = false;
  bool _cancelRequested = false;
  Completer<void>? _cancelSignal;
  String _status = '';
  OnDeviceTranslator? _translator;
  String? _result;
  String? _notice;
  File? _output;
  String? _error;

  /// True once the user pressed Hủy or left the screen.
  bool get _stopped => _cancelRequested || !mounted;

  @override
  void dispose() {
    _cancelRequested = true;
    _signalCancel();
    _translator?.close().ignore();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_running) return;
    try {
      final file = await pickPdfOrText();
      if (file == null || !mounted) return;
      setState(() {
        _input = file;
        _source = null;
        _result = null;
        _notice = null;
        _output = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Sets both languages at once; the pickers swap the two rather than
  /// allow the same language on both sides.
  void _setLanguages(TranslateLanguage from, TranslateLanguage to) =>
      setState(() {
        _from = from;
        _to = to;
      });

  void _cancel() {
    setState(() {
      _cancelRequested = true;
      _status = 'Đang dừng…';
    });
    _signalCancel();
  }

  void _signalCancel() {
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  void _setStatus(String status) {
    if (!_stopped) setState(() => _status = status);
  }

  /// [work]'s result, or null as soon as the user presses Hủy. The work
  /// itself can't be interrupted and finishes in the background.
  Future<T?> _unlessCancelled<T>(Future<T> work) {
    final signal = _cancelSignal;
    if (signal == null) return work;
    return Future.any<T?>([work, signal.future.then((_) => null)]);
  }

  Future<void> _run() async {
    final input = _input;
    if (input == null || _running) return;
    final from = _from;
    final to = _to;
    final signal = Completer<void>();
    _cancelSignal = signal;
    // Hủy stops waiting for the reading at once, but a scan's recognition
    // finishes its page first. It checks this run's own signal, so it still
    // stops when the next run has begun.
    bool cancelled() => signal.isCompleted || !mounted;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _status = 'Đang đọc chữ trong file…';
      _error = null;
      _result = null;
      _notice = null;
      _output = null;
    });
    OnDeviceTranslator? translator;
    final translated = <String>[];
    var scanned = false;
    var total = 0;
    // Pages finished, translated or skipped. The page being translated is
    // the one after them.
    var done = 0;
    var skipped = 0;

    // Shows the pages translated so far. `error` says why the translator
    // stopped early; without it, an early stop was the user's Hủy.
    void showTranslated({String? error}) {
      final notes = [
        if (error == null && done < total) 'Đã dừng sau trang $done/$total.',
        if (skipped > 0)
          'Bỏ qua $skipped trang không có chữ (trang trống hoặc chỉ có hình).',
        if (scanned) scannedTextNote,
      ];
      setState(() {
        _error = error;
        _result = translated.isEmpty ? null : translated.join('\n\n');
        _notice = notes.isEmpty ? null : notes.join(' ');
      });
    }

    try {
      final source =
          _source ??
          await _unlessCancelled<DocumentPages?>(
            readOrRecognizePages(
              input,
              onScanProgress: (i, n) =>
                  _setStatus(scanProgressText('File', i, n)),
              isCancelled: cancelled,
            ),
          );
      if (source == null || _stopped) return;
      _source = source;
      final texts = source.pages;
      scanned = source.scanned;
      if (texts.every((t) => t.trim().isEmpty)) {
        setState(
          () => _error = scanned
              ? 'Không tìm thấy chữ nào để dịch, kể cả khi đọc như bản scan. '
                    'Có thể file chỉ có hình, hoặc chữ quá mờ.'
              : 'File này không có chữ để dịch.',
        );
        return;
      }
      final problem = await _downloadMissing([from, to]);
      if (_stopped) return;
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }

      translator = OnDeviceTranslator(sourceLanguage: from, targetLanguage: to);
      _translator = translator;
      total = texts.length;
      for (; done < total && !_stopped; done++) {
        final chunks = translationChunks(texts[done]);
        if (chunks.isEmpty) {
          skipped++;
          continue;
        }
        _setStatus('Đang dịch trang ${done + 1}/$total');
        final parts = <String>[];
        for (final chunk in chunks) {
          // Hủy stops the wait at once; closing the translator below ends
          // the call still running.
          final text = await _unlessCancelled(translator.translateText(chunk));
          if (text == null || _stopped) break;
          parts.add(text.trim());
        }
        // Hủy mid-page drops that page, so the result ends on a whole page.
        if (_stopped) break;
        final page = parts.join('\n');
        translated.add(total > 1 ? '${pageMarker(done + 1)}\n$page' : page);
      }
      if (mounted && translated.isNotEmpty) showTranslated();
    } catch (e) {
      if (!mounted) return;
      final reason = friendlyError(e);
      if (translator == null) {
        setState(() => _error = reason);
      } else {
        // Keeps the pages already translated.
        showTranslated(
          error: total > 1
              ? 'Dừng ở trang ${done + 1}/$total vì bộ dịch gặp lỗi: $reason'
              : 'Bộ dịch gặp lỗi: $reason',
        );
      }
    } finally {
      _translator = null;
      await translator?.close().catchError((Object _) {});
      if (mounted) setState(() => _running = false);
    }
  }

  /// Downloads every language pack in [languages] that isn't on the device
  /// yet. Returns a message for the user when that fails, otherwise null
  /// (also after Hủy).
  Future<String?> _downloadMissing(List<TranslateLanguage> languages) async {
    final manager = OnDeviceTranslatorModelManager();
    for (final language in languages) {
      if (await manager.isModelDownloaded(language.bcpCode)) continue;
      if (_stopped) return null;
      _setStatus('Đang tải gói ngôn ngữ (chỉ lần đầu, cần Internet)…');
      if (!await _online()) {
        return 'Lần đầu dịch cần Internet để tải gói ngôn ngữ (khoảng 30 MB '
            'mỗi ngôn ngữ). Hãy bật Wi-Fi hoặc 4G rồi thử lại.';
      }
      final ok = await _unlessCancelled(_download(language));
      if (_stopped) return null;
      if (ok != true) {
        return 'Không tải được gói tiếng ${_languages[language]}. Hãy kiểm '
            'tra Internet rồi thử lại.';
      }
    }
    return null;
  }

  /// Starts the download of [language]'s pack, or joins the one already
  /// running. Completes with false on failure; never throws.
  static Future<bool> _download(TranslateLanguage language) =>
      _downloads[language] ??= OnDeviceTranslatorModelManager()
          // Mobile data is fine: the default waits for Wi-Fi on Android.
          .downloadModel(language.bcpCode, isWifiRequired: false)
          .catchError((Object _) => false)
          .whenComplete(() {
            _downloads.remove(language);
          });

  /// Whether the internet is reachable. Without a connection the Android
  /// download would sit waiting for one instead of failing.
  static Future<bool> _online() async {
    try {
      final hosts = await InternetAddress.lookup('www.google.com')
          .timeout(const Duration(seconds: 8));
      return hosts.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _copy() async {
    final text = _result;
    if (text == null) return;
    try {
      await copyText(context, text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _share() async {
    final text = _result;
    if (text == null) return;
    try {
      if (text.length <= _maxShareChars) {
        await SharePlus.instance.share(ShareParams(text: text));
        return;
      }
      final file = await _saveTxt();
      if (file == null) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Saves the result as a .txt file once and returns it; null on failure.
  Future<File?> _saveTxt() async {
    final text = _result;
    final input = _input;
    if (text == null || input == null) return null;
    final saved = _output;
    if (saved != null) return saved;
    File? out;
    try {
      out = await outputFile('${fileBaseName(input.path)}_dich', 'txt');
      await out.writeAsString(text);
      if (mounted) setState(() => _output = out);
      return out;
    } catch (e) {
      deleteQuietly(out);
      if (mounted) setState(() => _error = friendlyError(e));
      return null;
    }
  }

  Widget _languageField(
    String label,
    TranslateLanguage selected,
    ValueChanged<TranslateLanguage> onChanged,
  ) {
    return DropdownButtonFormField<TranslateLanguage>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final MapEntry(key: language, value: name) in _languages.entries)
          DropdownMenuItem(value: language, child: Text('Tiếng $name')),
      ],
      onChanged: _running
          ? null
          : (v) {
              if (v != null) onChanged(v);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final result = _result;
    final preview = result != null && result.length > _previewChars
        ? '${result.substring(0, _previewChars)}…'
        : result;
    return Scaffold(
      appBar: AppBar(title: const Text('Dịch PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Bản dịch giữ nội dung, không giữ bố cục trang. Chạy ngay trên máy.',
            style: muted,
          ),
          const SizedBox(height: 12),
          PickTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Chọn PDF (hoặc file .txt) cần dịch',
            picked: _input == null ? null : fileBaseName(_input!.path),
            onPick: _pick,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _languageField(
                      'Từ',
                      _from,
                      (v) => _setLanguages(v, v == _to ? _from : _to),
                    ),
                    const SizedBox(height: 12),
                    _languageField(
                      'Sang',
                      _to,
                      (v) => _setLanguages(v == _from ? _to : _from, v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.swap_vert_rounded),
                tooltip: 'Đổi chiều dịch',
                onPressed: _running ? null : () => _setLanguages(_to, _from),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_running)
            RunningPane(
              message: _status,
              onCancel: _cancelRequested ? null : _cancel,
            )
          else
            RunButton(
              label: 'Dịch sang tiếng ${_languages[_to]}',
              enabled: _input != null,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (result != null && preview != null) ...[
            if (_notice != null) ...[
              Text(_notice!, style: muted),
              const SizedBox(height: 8),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(preview),
              ),
            ),
            if (result.length > _previewChars) ...[
              const SizedBox(height: 4),
              Text(
                'Đang hiện phần đầu bản dịch. Bấm "Lưu .txt" hoặc "Chia sẻ" '
                'để lấy toàn bộ.',
                style: muted,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Sao chép'),
                    onPressed: _copy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Chia sẻ'),
                    onPressed: _share,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('Lưu .txt'),
              onPressed: _saveTxt,
            ),
            const SizedBox(height: 8),
          ],
          if (_output != null) ResultCard(file: _output!),
        ],
      ),
    );
  }
}

/// Longest piece sent to the translator in one call: enough context for a
/// good translation, short enough that Hủy takes effect within seconds.
const _maxChunk = 1000;

/// Paragraphs shorter than this travel with a neighbour, joined by a line
/// break, so headings and list items don't each cost a call.
const _minChunk = 200;

/// Han, kana and full-width forms. Chinese and Japanese put no spaces
/// between words, so their wrapped lines join without one. Korean does use
/// spaces, so Hangul isn't included.
final _noSpaceScript = RegExp(r'[\u2E80-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]');
final _hyphenatedEnd = RegExp(r'\p{L}-$', unicode: true);
final _lowercaseStart = RegExp(r'^\p{Ll}', unicode: true);
final _listItemStart = RegExp(r'^(?:[-•*·–—▪●○◦]|\d{1,3}[.)]|[a-zA-Z][.)])\s');
final _sentenceEnd = RegExp(r'[.!?…]+["”’)\]]*\s+|[。！？]+["”’」』)\]]*\s*');
final _blankLine = RegExp(r'\n[ \t]*\n');

/// Splits one page of extracted text into pieces for the translator.
///
/// PDF text arrives as wrapped lines, which translate badly one by one, so
/// lines are joined back into paragraphs. A paragraph ends at a blank line,
/// before a list item, or after a line clearly shorter than the block's
/// typical line (a line that stops early wasn't wrapped: it ends a
/// paragraph or is a heading). Paragraphs over [_maxChunk] characters are
/// cut at sentence ends, and short neighbours are merged.
@visibleForTesting
List<String> translationChunks(String pageText) {
  final paragraphs = <String>[];
  final text = pageText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final block in text.split(_blankLine)) {
    final lines = [
      for (final line in block.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) continue;
    final lengths = [for (final line in lines) line.length]..sort();
    final typical = lengths[lengths.length ~/ 2];
    var current = '';
    for (final line in lines) {
      if (current.isNotEmpty && _listItemStart.hasMatch(line)) {
        paragraphs.addAll(_splitLong(current));
        current = '';
      }
      current = current.isEmpty ? line : _joinText(current, line);
      if (line.length < typical * 0.6 && !_hyphenatedEnd.hasMatch(line)) {
        paragraphs.addAll(_splitLong(current));
        current = '';
      }
    }
    if (current.isNotEmpty) paragraphs.addAll(_splitLong(current));
  }

  final chunks = <String>[];
  var pending = '';
  for (final paragraph in paragraphs) {
    if (pending.isEmpty) {
      pending = paragraph;
    } else if ((pending.length < _minChunk || paragraph.length < _minChunk) &&
        pending.length + 1 + paragraph.length <= _maxChunk) {
      pending = '$pending\n$paragraph';
    } else {
      chunks.add(pending);
      pending = paragraph;
    }
  }
  if (pending.isNotEmpty) chunks.add(pending);
  return chunks;
}

/// Joins two runs of text: undoes a hyphen that split a word across lines,
/// and adds no space next to Chinese or Japanese characters.
String _joinText(String a, String b) {
  if (_hyphenatedEnd.hasMatch(a) && _lowercaseStart.hasMatch(b)) {
    return '${a.substring(0, a.length - 1)}$b';
  }
  if (_noSpaceScript.hasMatch(a[a.length - 1]) ||
      _noSpaceScript.hasMatch(b[0])) {
    return '$a$b';
  }
  return '$a $b';
}

/// [paragraph] in pieces of at most [_maxChunk] characters, cut at sentence
/// ends, or at spaces inside a sentence that is longer than a piece.
List<String> _splitLong(String paragraph) {
  if (paragraph.length <= _maxChunk) return [paragraph];
  final pieces = <String>[];
  var pending = '';
  void add(String sentence) {
    if (pending.isEmpty) {
      pending = sentence;
    } else if (pending.length + 1 + sentence.length <= _maxChunk) {
      pending = _joinText(pending, sentence);
    } else {
      pieces.add(pending);
      pending = sentence;
    }
  }

  var start = 0;
  final ends = [
    for (final m in _sentenceEnd.allMatches(paragraph)) m.end,
    paragraph.length,
  ];
  for (final end in ends) {
    var sentence = paragraph.substring(start, end).trim();
    start = end;
    while (sentence.length > _maxChunk) {
      var cut = sentence.lastIndexOf(' ', _maxChunk);
      if (cut <= 0) cut = _maxChunk;
      add(sentence.substring(0, cut).trim());
      sentence = sentence.substring(cut).trim();
    }
    if (sentence.isNotEmpty) add(sentence);
  }
  if (pending.isNotEmpty) pieces.add(pending);
  return pieces;
}
