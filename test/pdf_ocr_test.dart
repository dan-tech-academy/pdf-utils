import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_utils/pdf_ocr.dart';

final _pdf = File('scan.pdf');
const _text =
    'Hợp đồng này được lập thành hai bản có giá trị pháp lý như nhau, '
    'mỗi bên giữ một bản để thực hiện.';

void main() {
  test('a PDF with text on its pages is not read with OCR', () {
    expect(pagesToRecognize(_pdf, [_text, _text, _text]), isEmpty);
  });

  test('a scan with no text layer is read page by page', () {
    expect(pagesToRecognize(_pdf, ['', ' \n', '']), [0, 1, 2]);
  });

  test('a scanner app line does not count as a text layer', () {
    const stamp = 'Scanned with CamScanner';
    expect(pagesToRecognize(_pdf, [stamp, stamp, '3']), [0, 1, 2]);
  });

  test('a document with a few picture pages keeps its text', () {
    expect(pagesToRecognize(_pdf, [_text, '', _text, _text]), isEmpty);
  });

  test('mostly scanned pages are read, real text pages are kept', () {
    expect(pagesToRecognize(_pdf, ['', _text, '']), [0, 2]);
  });

  test('saved text files are never read with OCR', () {
    expect(pagesToRecognize(File('ocr.txt'), ['', '']), isEmpty);
  });
}
