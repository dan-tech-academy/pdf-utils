import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_utils/diacritics.dart';
import 'package:pdf_utils/errors.dart';
import 'package:pdf_utils/files.dart';
import 'package:pdf_utils/page_text.dart';
import 'package:pdf_utils/screens/web_to_pdf_screen.dart';

void main() {
  test('removeDiacritics folds Vietnamese, precomposed and decomposed', () {
    expect(removeDiacritics('Tiếng Việt'), 'Tieng Viet');
    expect(removeDiacritics('Hợp đồng lao động'), 'Hop dong lao dong');
    expect(removeDiacritics('ĐƯỜNG Phố Ẩm Thực'), 'DUONG Pho Am Thuc');
    // "Hợp" as base letters plus combining horn and dot below (NFD).
    expect(removeDiacritics('Ho\u031B\u0323p'), 'Hop');
    expect(removeDiacritics('report-2026_v2'), 'report-2026_v2');
  });

  test('composeVietnamese joins letters typed as base + marks', () {
    // "Hợp đồng" typed with combining marks, in two different mark orders.
    expect(composeVietnamese('Ho\u031B\u0323p đo\u0302\u0300ng'), 'Hợp đồng');
    expect(composeVietnamese('Ho\u0323\u031Bp'), 'Hợp');
    expect(composeVietnamese('ê\u0301 Ư\u0300'), 'ế Ừ');
    expect(composeVietnamese('Hợp đồng'), 'Hợp đồng');
    // Not Vietnamese: left alone.
    expect(composeVietnamese('c\u0327'), 'c\u0327');
  });

  test('page markers split and join back without running headers', () {
    final saved = [
      for (var p = 1; p <= 4; p++)
        '${pageMarker(p)}\n'
            'CÔNG TY ABC\n'
            'Điều $p. Nội dung điều khoản thứ $p của hợp đồng này.\n'
            'Các bên cam kết thực hiện đúng.\n'
            'Ghi chú riêng cho trang số $p của bản hợp đồng này.\n'
            'Trang $p/4',
    ].join('\n');
    final pages = splitPageMarkers(saved);
    expect(pages, hasLength(4));
    expect(pages.first, startsWith('CÔNG TY ABC'));
    final joined = joinPages(pages);
    expect(joined, isNot(contains('CÔNG TY ABC')));
    expect(joined, isNot(contains('/4')));
    // Long lines that differ only in numbers are body text, not headers.
    expect(joined, contains('Điều 4. Nội dung điều khoản thứ 4'));
    expect(joined, contains('Ghi chú riêng cho trang số 4 của bản'));
    expect(joined.split('\n\n'), hasLength(4));
    // Too few pages to call a line "running": nothing is dropped.
    expect(joinPages(pages.take(2).toList()), contains('CÔNG TY ABC'));
    // Pages too short to hold a header and a body stay whole.
    expect(joinPages(['a\nb', 'a\nb', 'a\nb']), 'a\nb\n\na\nb\n\na\nb');
    expect(splitPageMarkers('Không có dấu trang'), ['Không có dấu trang']);
  });

  test('safeFileStem keeps Vietnamese names readable', () {
    expect(safeFileStem('Hợp đồng.pdf_nen'), 'Hop_dong_nen');
    expect(safeFileStem('Báo cáo (bản 2).PDF_cat'), 'Bao_cao_ban_2_cat');
    expect(safeFileStem('scan.jpg'), 'scan');
    expect(safeFileStem('  ...  '), 'pdf');
  });

  test('parseWebAddress accepts what people type or paste', () {
    expect(
      parseWebAddress('vnexpress.net/bai-viet')?.toString(),
      'https://vnexpress.net/bai-viet',
    );
    expect(
      parseWebAddress('Đọc bài này: https://tuoitre.vn/abc.htm, hay lắm!')
          ?.toString(),
      'https://tuoitre.vn/abc.htm',
    );
    expect(parseWebAddress('http://example.com')?.scheme, 'http');
    expect(parseWebAddress('hello world'), isNull);
    expect(parseWebAddress('vnexpress'), isNull);
    expect(parseWebAddress('ftp://example.com/file'), isNull);
  });

  test('friendlyError explains common failures in Vietnamese', () {
    expect(friendlyError(const PdfPasswordRequired()), contains('mật khẩu'));
    expect(
      friendlyError(const PdfCorrupted('bad xref')),
      contains('Sửa PDF lỗi'),
    );
    expect(friendlyError(StateError('x')), startsWith('Có lỗi xảy ra'));
  });
}
