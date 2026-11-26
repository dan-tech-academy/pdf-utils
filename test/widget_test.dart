import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_utils/main.dart';

void main() {
  testWidgets('Home shows tool grid', (tester) async {
    await tester.pumpWidget(const PdfUtilsApp());
    await tester.pumpAndSettle();

    expect(find.text('PDF Utils'), findsOneWidget);
    for (final t in [
      'Nén PDF',
      'Ghép PDF',
      'Tách PDF',
      'Chèn ảnh',
      'Scan → PDF',
      'Ảnh → PDF',
      'Khóa / Mở khóa',
      'Xoay PDF',
      'Dịch PDF',
      'So sánh PDF',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
  });

  testWidgets('Search finds tools without accents', (tester) async {
    await tester.pumpWidget(const PdfUtilsApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nen');
    await tester.pump();
    expect(find.text('Nén PDF'), findsOneWidget);
    expect(find.text('Ghép PDF'), findsNothing);

    // "word" must not find "password" (a keyword of Khóa / Mở khóa).
    await tester.enterText(find.byType(TextField), 'word');
    await tester.pump();
    expect(find.text('PDF ↔ Word, Excel, PPT'), findsOneWidget);
    expect(find.text('Khóa / Mở khóa'), findsNothing);

    // "Chỉnh sửa PDF" also mentions both words, but the tool named by the
    // query must come first.
    await tester.enterText(find.byType(TextField), 'dong dau');
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Đóng dấu chữ')).dy,
      lessThan(tester.getTopLeft(find.text('Chỉnh sửa PDF')).dy),
    );

    await tester.enterText(find.byType(TextField), 'xyz không có');
    await tester.pump();
    expect(find.textContaining('Không có công cụ nào khớp'), findsOneWidget);
  });
}
