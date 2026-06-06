import 'package:act_dart_primary_constructors/src/source_edit.dart';
import 'package:test/test.dart';

void main() {
  group('source edits', () {
    test('applies insertions, replacements, and deletions descending', () {
      final result = applySourceEdits('abcdef', [
        const SourceEdit.insert(1, 'X'),
        SourceEdit.replace(SourceRange(offset: 3, length: 1), 'Y'),
        SourceEdit.delete(SourceRange(offset: 5, length: 1)),
      ]);

      expect(result, 'aXbcYe');
    });

    test('applies equal-offset insertions in input order', () {
      final result = applySourceEdits('ab', const [
        SourceEdit.insert(1, 'X'),
        SourceEdit.insert(1, 'Y'),
      ]);

      expect(result, 'aXYb');
    });

    test(
      'applies equal-offset start-boundary insertions before replacement',
      () {
        final result = applySourceEdits('abcd', [
          const SourceEdit.insert(1, 'X'),
          const SourceEdit.insert(1, 'Y'),
          SourceEdit.replace(SourceRange(offset: 1, length: 2), 'Z'),
        ]);

        expect(result, 'aXYZd');
      },
    );

    test('rejects overlapping edits', () {
      expect(
        () => applySourceEdits('abcdef', [
          SourceEdit.replace(SourceRange(offset: 1, length: 3), 'X'),
          SourceEdit.replace(SourceRange(offset: 3, length: 1), 'Y'),
        ]),
        throwsA(isA<SourceEditException>()),
      );
    });

    test(
      'rejects duplicate equal-offset replacements as overlapping edits',
      () {
        expect(
          () => applySourceEdits('abcdef', [
            SourceEdit.replace(SourceRange(offset: 1, length: 2), 'X'),
            SourceEdit.replace(SourceRange(offset: 1, length: 2), 'Y'),
          ]),
          throwsA(
            isA<SourceEditException>().having(
              (error) => error.message,
              'message',
              'Edit range 1..3 overlaps 1..3.',
            ),
          ),
        );
      },
    );

    test('rejects invalid ranges with stable failures', () {
      void expectFailure(List<SourceEdit> edits, String message) {
        expect(
          () => applySourceEdits('abcdef', edits),
          throwsA(
            isA<SourceEditException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
      }

      expectFailure(const [
        SourceEdit.insert(-1, 'X'),
      ], 'Edit offset -1 is outside source bounds 0..6.');
      expectFailure(const [
        SourceEdit.insert(7, 'X'),
      ], 'Edit offset 7 is outside source bounds 0..6.');
      expectFailure(const [
        SourceEdit(offset: 1, length: -1, replacement: 'X'),
      ], 'Edit length -1 is negative.');
      expectFailure([
        SourceEdit.replace(SourceRange(offset: 5, length: 2), 'X'),
      ], 'Edit range 5..7 is outside source bounds 0..6.');
    });
  });
}
