import 'package:dart_primary_constructors/src/source_edit.dart';
import 'package:test/test.dart';

void main() {
  group('source edits', () {
    test('applies insertions, replacements, and deletions descending', () {
      final result = applySourceEdits('abcdef', const [
        SourceEdit(offset: 1, length: 0, replacement: 'X'),
        SourceEdit(offset: 3, length: 1, replacement: 'Y'),
        SourceEdit(offset: 5, length: 1, replacement: ''),
      ]);

      expect(result, 'aXbcYe');
    });

    test('rejects overlapping edits', () {
      expect(
        () => applySourceEdits('abcdef', const [
          SourceEdit(offset: 1, length: 3, replacement: 'X'),
          SourceEdit(offset: 3, length: 1, replacement: 'Y'),
        ]),
        throwsA(isA<SourceEditException>()),
      );
    });
  });
}
