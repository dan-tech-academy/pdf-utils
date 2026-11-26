import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' show PdfError;
import 'package:printing/printing.dart' show Printing;

import '../engine.dart';
import '../errors.dart';
import '../files.dart';
import '../widgets.dart';

/// Longest wait for the page, from connecting to its last byte.
const _fetchTimeout = Duration(seconds: 20);

/// Longest wait for the platform web view to lay the page out and print it;
/// the page's images and styles load during this step.
const _convertTimeout = Duration(seconds: 90);

/// Largest PDF accepted, so a wrong link can't exhaust memory.
const _maxPdfBytes = 50 * 1024 * 1024;

/// Largest web page accepted: the whole page goes through the web view.
const _maxHtmlBytes = 10 * 1024 * 1024;

/// Content types a downloadable PDF arrives with; "tải về" links on many
/// sites send the generic binary types, so the body is checked as well.
const _pdfTypes = {
  'application/pdf',
  'application/x-pdf',
  'application/octet-stream',
  'binary/octet-stream',
};

/// Sent as the browser name: some sites refuse or strip pages for clients
/// that don't look like a browser. A phone browser gets the single-column
/// layout, which suits an A4 page best.
const _userAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

const _badAddress =
    'Địa chỉ trang web chưa đúng. Hãy nhập dạng: vnexpress.net/bai-viet';
const _tooLarge = 'Trang này quá lớn, không tải được.';

/// Saves a web page (a news article, a notice) as an A4 PDF. The HTML is
/// downloaded here, then laid out and printed by the platform web view.
class WebToPdfScreen extends StatefulWidget {
  const WebToPdfScreen({super.key});

  @override
  State<WebToPdfScreen> createState() => _WebToPdfScreenState();
}

class _WebToPdfScreenState extends State<WebToPdfScreen> {
  final _url = TextEditingController();
  bool _running = false;
  String _status = '';
  File? _output;
  int? _pageCount;
  String? _error;

  /// The run in flight: completing [_cancel] stops waiting on it, and
  /// closing [_client] stops its download.
  Completer<void>? _cancel;
  HttpClient? _client;

  @override
  void dispose() {
    _stop();
    _url.dispose();
    super.dispose();
  }

  void _stop() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _client?.close(force: true);
  }

  void _cancelRun() {
    _stop();
    setState(() {
      _running = false;
      _status = '';
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted || text.isEmpty) return;
    setState(() {
      _url.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _error = null;
    });
  }

  Future<void> _run() async {
    if (_running || _url.text.trim().isEmpty) return;
    final url = parseWebAddress(_url.text);
    if (url == null) {
      setState(() {
        _error = _badAddress;
        _output = null;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final cancel = _cancel = Completer<void>();
    final client = _client = HttpClient()
      ..connectionTimeout = _fetchTimeout
      ..userAgent = _userAgent;
    setState(() {
      _running = true;
      _status = 'Đang tải trang web…';
      _error = null;
      _output = null;
    });
    File? out;
    try {
      final page = await _download(client, url);
      if (cancel.isCompleted || !mounted) return;
      out = await outputFile('${_hostStem(page.url)}_web', 'pdf');
      if (page.isPdf) {
        // The link points at a PDF already: keep it as it is.
        await out.writeAsBytes(page.body, flush: true);
      } else {
        setState(() => _status = 'Đang tạo PDF…');
        // printing deprecated convertHtml in favour of drawing PDFs with its
        // widgets, which can't lay out a web page. It is still the only
        // on-device web page → PDF path, and its native side is maintained
        // (5.15.1 fixed it for iOS 26).
        final pdf = await _unlessCancelled(
          cancel,
          // ignore: deprecated_member_use
          Printing.convertHtml(
            html: _decodeHtml(page.body, page.charset),
            baseUrl: page.url.toString(),
          ).timeout(_convertTimeout),
        );
        if (pdf == null || !mounted) return;
        await out.writeAsBytes(pdf, flush: true);
      }
      final pages = await _countPages(out);
      if (!mounted) return;
      setState(() {
        _output = out;
        _pageCount = pages;
      });
    } catch (e) {
      deleteQuietly(out);
      // A cancel closes the connection, which fails the download: no error.
      if (mounted && !cancel.isCompleted) {
        setState(() => _error = _messageFor(e));
      }
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
      if (mounted) setState(() => _running = false);
    }
  }

  static String _messageFor(Object error) => switch (error) {
    _PageError(:final message) => message,
    RedirectException() =>
      'Trang web này chuyển hướng quá nhiều lần nên không tải được.',
    HandshakeException() =>
      'Không kiểm tra được chứng chỉ bảo mật của trang web này nên không tải '
          'được.',
    // A wrong address fails the same way as a missing connection.
    SocketException() =>
      'Không mở được trang web. Hãy kiểm tra lại địa chỉ và kết nối '
          'Internet.',
    // The web view reports its own failures as plain text.
    String() || PlatformException() =>
      'Không chuyển được trang này sang PDF. Hãy thử lại hoặc thử trang '
          'khác.',
    _ => friendlyError(error),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = _pageCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Trang web → PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Hợp với bài báo, trang tin. Trang phải đăng nhập sẽ không tải '
            'được.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            enabled: !_running,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Địa chỉ trang web',
              hintText: 'vd: vnexpress.net/bai-viet…',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste_rounded),
                tooltip: 'Dán',
                onPressed: _running ? null : _paste,
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _run(),
          ),
          const SizedBox(height: 16),
          if (_running)
            RunningPane(message: _status, onCancel: _cancelRun)
          else
            RunButton(
              label: 'Tạo PDF',
              enabled: _url.text.trim().isNotEmpty,
              onPressed: _run,
            ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(message: _error!),
          if (_output != null)
            ResultCard(
              file: _output!,
              extra: pages == null ? null : '$pages trang',
            ),
        ],
      ),
    );
  }
}

/// The web address in what the user typed or pasted: the first http(s) link
/// of pasted text with words around it, or else the whole entry, with
/// `https://` added when it has no scheme. Null when it can't be a web
/// address.
Uri? parseWebAddress(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  var candidate = text;
  if (text.contains(RegExp(r'\s'))) {
    final link = RegExp(
      r'https?://\S+',
      caseSensitive: false,
    ).firstMatch(text)?.group(0);
    if (link == null) return null;
    // Drop the punctuation that ends the sentence around the link.
    candidate = link.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
  } else if (!RegExp(
    r'^[a-z][a-z0-9+.\-]*://',
    caseSensitive: false,
  ).hasMatch(text)) {
    candidate = 'https://$text';
  }
  final url = Uri.tryParse(candidate);
  if (url == null ||
      (url.scheme != 'http' && url.scheme != 'https') ||
      !url.host.contains('.')) {
    return null;
  }
  return url;
}

/// A downloaded page: the address it ended at after redirects, its body,
/// the charset the server named, and whether the link was a PDF already.
typedef _Download = ({Uri url, Uint8List body, String? charset, bool isPdf});

/// Downloads [url] with [client], following redirects, all within
/// [_fetchTimeout]. The caller closes [client], which also stops a download
/// still running after a timeout or a cancel.
Future<_Download> _download(HttpClient client, Uri url) =>
    _get(client, url).timeout(_fetchTimeout);

/// [work]'s value, or null when [cancel] completes first; the work's own
/// later result or error is dropped.
Future<T?> _unlessCancelled<T>(Completer<void> cancel, Future<T> work) =>
    Future.any([
      work.then<T?>((value) => value),
      cancel.future.then<T?>((_) => null),
    ]);

Future<_Download> _get(HttpClient client, Uri url) async {
  final request = await client.getUrl(url);
  request
    ..followRedirects = true
    ..headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8',
    )
    ..headers.set(HttpHeaders.acceptLanguageHeader, 'vi,en;q=0.8');
  final response = await request.close();

  // A redirect target may be relative to the address before it.
  var finalUrl = url;
  for (final redirect in response.redirects) {
    finalUrl = finalUrl.resolveUri(redirect.location);
  }

  final status = response.statusCode;
  if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
    throw const _PageError(
      'Trang này cần đăng nhập hoặc không cho tải về nên không lấy được.',
    );
  }
  if (status == HttpStatus.notFound || status == HttpStatus.gone) {
    throw const _PageError(
      'Không tìm thấy trang này. Hãy kiểm tra lại địa chỉ.',
    );
  }
  if (status < 200 || status >= 300) {
    throw _PageError('Trang web đang báo lỗi (mã $status). Hãy thử lại sau.');
  }

  final type = response.headers.contentType;
  // A server that names no type almost always sends a page.
  final mime = type?.mimeType ?? 'text/html';
  const notPage = _PageError('Địa chỉ này không phải trang web hay file PDF.');
  final maybePdf = _pdfTypes.contains(mime);
  if (!maybePdf && mime != 'text/html' && mime != 'application/xhtml+xml') {
    throw notPage;
  }
  final body = await _readBody(
    response,
    maybePdf ? _maxPdfBytes : _maxHtmlBytes,
  );
  final isPdf = maybePdf && _looksLikePdf(body);
  if (maybePdf && !isPdf) {
    throw mime == 'application/pdf'
        ? const _PageError('File PDF ở địa chỉ này bị hỏng, không lưu được.')
        : notPage;
  }
  return (url: finalUrl, body: body, charset: type?.charset, isPdf: isPdf);
}

/// The response body, refusing anything over [limit] bytes.
Future<Uint8List> _readBody(HttpClientResponse response, int limit) async {
  if (response.contentLength > limit) throw const _PageError(_tooLarge);
  final body = BytesBuilder(copy: false);
  await for (final chunk in response) {
    body.add(chunk);
    if (body.length > limit) throw const _PageError(_tooLarge);
  }
  return body.takeBytes();
}

/// Whether [bytes] hold a PDF: its `%PDF-` header may follow up to a
/// kilobyte of other bytes.
bool _looksLikePdf(Uint8List bytes) =>
    latin1.decode(bytes.take(1024).toList()).contains('%PDF-');

/// [bytes] as text in the charset the server named, or as UTF-8 (which
/// covers ASCII), tolerating bad bytes, when it named none Dart knows.
String _decodeHtml(Uint8List bytes, String? charset) {
  final encoding = Encoding.getByName(charset);
  if (encoding == null || encoding == utf8 || encoding == ascii) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  return encoding.decode(bytes);
}

/// The page's host for the file name: "www.vnexpress.net" → "vnexpress-net".
String _hostStem(Uri url) {
  final host = url.host
      .replaceFirst(RegExp(r'^www\.'), '')
      .replaceAll('.', '-');
  return host.isEmpty ? 'trang_web' : host;
}

/// Page count of [file] for the result line; null when the engine can't
/// read it (a downloaded PDF may be locked), which only hides that line.
Future<int?> _countPages(File file) async {
  try {
    return (await PdfEngine.instance.pageInfo(file)).length;
  } on PdfError {
    return null;
  }
}

/// A page that was reached but can't be saved; [message] tells the user
/// why, in Vietnamese.
class _PageError implements Exception {
  const _PageError(this.message);

  final String message;
}
