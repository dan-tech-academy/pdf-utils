import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_utils/screens/translate_screen.dart';

void main() {
  test('wrapped lines join back into one paragraph', () {
    expect(
      translationChunks(
        'This is a long line of text that wraps\n'
        'onto the next line and continues here\n'
        'until it ends.',
      ),
      [
        'This is a long line of text that wraps onto the next line and '
            'continues here until it ends.',
      ],
    );
  });

  test('a hyphen that split a word across lines is undone', () {
    expect(
      translationChunks('The inter-\nnational trade agreement is signed now.'),
      ['The international trade agreement is signed now.'],
    );
  });

  test('short paragraphs and list items travel together', () {
    expect(translationChunks('Heading\n\nShort paragraph.'), [
      'Heading\nShort paragraph.',
    ]);
    expect(translationChunks('- one\n- two'), ['- one\n- two']);
  });

  test('Chinese lines join without a space', () {
    expect(translationChunks('这是第一行\n这是第二行'), ['这是第一行这是第二行']);
  });

  test('long text is cut at sentence ends into pieces of at most 1000', () {
    final sentence = 'Câu này dài vừa phải để thử cách cắt đoạn văn. ';
    final chunks = translationChunks(sentence * 60);
    expect(chunks.length, greaterThan(1));
    for (final c in chunks) {
      expect(c.length, lessThanOrEqualTo(1000));
      expect(c, endsWith('.'));
    }
    expect(chunks.join(' '), (sentence * 60).trim());
  });

  test('a blank page gives no chunks', () {
    expect(translationChunks('  \n\n \n'), isEmpty);
  });
}
