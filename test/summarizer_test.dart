import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_utils/summarizer.dart';

const _english = [
  'The city council approved a new budget for public parks and libraries '
      'this week.',
  'Local residents said the parks need more trees and better lighting at '
      'night.',
  'The libraries will extend their opening hours and add new books for '
      'children.',
  'Council members argued for months about how to fund the parks and the '
      'libraries.',
  'The new budget for parks and libraries is the largest in a decade, the '
      'council said.',
  'A local bakery also won an award for its bread at the regional fair.',
];

const _vietnamese = [
  'Hợp đồng thuê nhà được ký giữa ông An và bà Bình vào ngày 15 tháng 2.',
  'Giá thuê nhà là 8 triệu đồng mỗi tháng, thanh toán vào đầu tháng.',
  'Bà Bình có trách nhiệm sửa chữa nhà khi có hư hỏng lớn.',
  'Ông An phải giữ gìn nhà sạch sẽ và không được cho người khác thuê lại.',
  'Hợp đồng thuê nhà có thời hạn hai năm và có thể gia hạn nếu hai bên '
      'đồng ý.',
  'Hôm qua trời mưa to ở Đà Lạt suốt buổi chiều.',
];

/// Letter-only made-up syllables, so no sentence looks like a page header.
final _syllables = [
  for (final c in 'bcdghklmnp'.split(''))
    for (final v in 'aeiou'.split(''))
      for (final end in ['', 'n', 'm', 't', 'c', 'p', 'ng', 'nh']) '$c$v$end',
];

void main() {
  group('summarize', () {
    test('picks the sentences most connected to the rest (English)', () {
      final text = _english.join('\n');
      expect(summarize(text, maxSentences: 1), [_english[4]]);
      expect(summarize(text, maxSentences: 2), [_english[0], _english[4]]);
      for (var n = 1; n <= 5; n++) {
        expect(summarize(text, maxSentences: n), isNot(contains(_english[5])));
      }
    });

    test('picks the sentences most connected to the rest (Vietnamese)', () {
      final text = _vietnamese.join(' ');
      expect(summarize(text, maxSentences: 1), [_vietnamese[0]]);
      expect(summarize(text, maxSentences: 3), [
        _vietnamese[0],
        _vietnamese[1],
        _vietnamese[4],
      ]);
      for (var n = 1; n <= 5; n++) {
        expect(
          summarize(text, maxSentences: n),
          isNot(contains(_vietnamese[5])),
        );
      }
    });

    test('fewer sentences than asked come back whole, minus fragments', () {
      expect(
        summarize(
          'Báo cáo quý 3.\nDoanh thu tăng 12% so với cùng kỳ năm trước. Chi '
          'phí vận chuyển giảm nhờ đổi nhà cung cấp mới. Công ty dự kiến mở '
          'thêm hai cửa hàng trong năm tới.\nTrân trọng.',
          maxSentences: 10,
        ),
        [
          'Doanh thu tăng 12% so với cùng kỳ năm trước.',
          'Chi phí vận chuyển giảm nhờ đổi nhà cung cấp mới.',
          'Công ty dự kiến mở thêm hai cửa hàng trong năm tới.',
        ],
      );
      expect(
        summarize(
          'Thanks. The meeting moved to Friday because the room was booked.\n'
          'Please bring the signed contract and your notes.',
        ),
        [
          'The meeting moved to Friday because the room was booked.',
          'Please bring the signed contract and your notes.',
        ],
      );
    });

    test('nothing to summarise gives an empty list', () {
      expect(summarize(''), isEmpty);
      expect(summarize('  \n\n '), isEmpty);
      expect(summarize('Xin chào. Cảm ơn bạn. Hẹn gặp lại.'), isEmpty);
      expect(summarize(_english.join(' '), maxSentences: 0), isEmpty);
    });

    test('skips running headers and footers, counts a repeat once', () {
      // Facts that differ only in their numbers all stay.
      final content = [
        for (var q = 1; q <= 3; q++)
          'Doanh thu quý $q tăng ${q * 2}% nhờ xuất khẩu sang châu Âu.',
      ];
      const repeated = 'Ban lãnh đạo đặt mục tiêu tăng trưởng hai con số.';
      final text = [
        for (var page = 1; page <= 3; page++) ...[
          'CÔNG TY CỔ PHẦN AN PHÁT - BÁO CÁO THƯỜNG NIÊN 2025 - TRANG $page',
          content[page - 1],
          'Tài liệu này chỉ dùng trong nội bộ công ty.',
        ],
        repeated,
        repeated,
      ].join('\n');
      expect(summarize(text, maxSentences: 20), [...content, repeated]);
    });

    test('long texts are narrowed first and still summarised fast', () {
      final random = Random(3);
      String word() =>
          _syllables[(pow(random.nextDouble(), 2) * _syllables.length).floor()];
      final sentences = [
        for (var i = 0; i < 3000; i++)
          'Câu ${[for (var k = 8 + random.nextInt(12); k > 0; k--) word()].join(' ')} xong.',
      ];
      final text = sentences.join(' ');
      final watch = Stopwatch()..start();
      final summary = summarize(text);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(summary, hasLength(7));
      final positions = [for (final s in summary) sentences.indexOf(s)];
      expect(positions, everyElement(greaterThanOrEqualTo(0)));
      expect(positions, [...positions]..sort());
      expect(summarize(text), summary, reason: 'same text, same summary');
    });
  });

  group('splitSentences', () {
    test('joins lines broken by the page width', () {
      expect(
        splitSentences(
          'Hợp đồng này có hiệu lực\nkể từ ngày ký. Hai bên cam kết\r\n'
          'thực hiện đúng các điều khoản.',
        ),
        [
          'Hợp đồng này có hiệu lực kể từ ngày ký.',
          'Hai bên cam kết thực hiện đúng các điều khoản.',
        ],
      );
      // A capital at the start of a line can still continue a full line.
      expect(
        splitSentences(
          'Hợp đồng được ký kết giữa Công ty Cổ phần An Phát và\n'
          'Công ty TNHH Bình Minh vào ngày 15 tháng 2 năm 2026.',
        ),
        [
          'Hợp đồng được ký kết giữa Công ty Cổ phần An Phát và Công ty TNHH '
              'Bình Minh vào ngày 15 tháng 2 năm 2026.',
        ],
      );
    });

    test('headings, list items and blank lines start new sentences', () {
      expect(
        splitSentences(
          'Điều 1. Phạm vi áp dụng\n'
          'Hợp đồng này quy định quyền và nghĩa vụ của hai bên khi thuê nhà.\n'
          'Bên A có nghĩa vụ:\n'
          '- Thanh toán tiền thuê nhà đúng hạn;\n'
          '• Giữ gìn tài sản chung.\n'
          '\n'
          'Điều 2. Thời hạn',
        ),
        [
          'Điều 1.',
          'Phạm vi áp dụng',
          'Hợp đồng này quy định quyền và nghĩa vụ của hai bên khi thuê nhà.',
          'Bên A có nghĩa vụ:',
          'Thanh toán tiền thuê nhà đúng hạn;',
          'Giữ gìn tài sản chung.',
          'Điều 2.',
          'Thời hạn',
        ],
      );
    });

    test('abbreviations and numbers do not end a sentence', () {
      expect(
        splitSentences(
          'Công ty có trụ sở tại P. Bến Nghé, Q. 1, TP. Hồ Chí Minh, do TS. '
          'Nguyễn Văn An điều hành. Vốn điều lệ là 1.500.000.000 đồng, tức '
          '1.5 tỷ. Mr. Smith joined in 2020.',
        ),
        [
          'Công ty có trụ sở tại P. Bến Nghé, Q. 1, TP. Hồ Chí Minh, do TS. '
              'Nguyễn Văn An điều hành.',
          'Vốn điều lệ là 1.500.000.000 đồng, tức 1.5 tỷ.',
          'Mr. Smith joined in 2020.',
        ],
      );
      // Contracts end sentences on a single capital.
      expect(
        splitSentences('Bên B trả tiền thuê cho Bên A. Bên B được đậu xe.'),
        ['Bên B trả tiền thuê cho Bên A.', 'Bên B được đậu xe.'],
      );
    });

    test('question marks, ellipses, quotes and lowercase continuations', () {
      expect(
        splitSentences(
          'Did he bring the report? Yes… it was late! She said: "We will '
          'sign tomorrow." Then they left.',
        ),
        [
          'Did he bring the report?',
          'Yes… it was late!',
          'She said: "We will sign tomorrow."',
          'Then they left.',
        ],
      );
      expect(
        splitSentences(
          'Các loại giấy tờ, v.v. đều phải nộp bản gốc. Cần mang theo bút, '
          'giấy, v.v. Các em nhớ đến đúng giờ.',
        ),
        [
          'Các loại giấy tờ, v.v. đều phải nộp bản gốc.',
          'Cần mang theo bút, giấy, v.v.',
          'Các em nhớ đến đúng giờ.',
        ],
      );
    });
  });
}
