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
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
  });
}
