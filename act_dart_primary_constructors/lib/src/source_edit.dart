class SourceEdit {
  const SourceEdit({
    required this.offset,
    required this.length,
    required this.replacement,
  });

  final int offset;
  final int length;
  final String replacement;

  int get end => offset + length;
}

class SourceEditException implements Exception {
  const SourceEditException(this.message);

  final String message;

  @override
  String toString() => 'SourceEditException: $message';
}

String applySourceEdits(String source, List<SourceEdit> edits) {
  validateSourceEdits(source, edits);
  final orderedEdits = [...edits]
    ..sort((a, b) {
      final byOffset = b.offset.compareTo(a.offset);
      if (byOffset != 0) {
        return byOffset;
      }
      return b.length.compareTo(a.length);
    });

  var result = source;
  for (final edit in orderedEdits) {
    result = result.replaceRange(edit.offset, edit.end, edit.replacement);
  }
  return result;
}

void validateSourceEdits(String source, List<SourceEdit> edits) {
  final orderedEdits = [...edits]..sort((a, b) => a.offset.compareTo(b.offset));
  SourceEdit? previous;
  for (final edit in orderedEdits) {
    if (edit.offset < 0 || edit.length < 0 || edit.end > source.length) {
      throw SourceEditException(
        'Edit range ${edit.offset}..${edit.end} is outside source bounds.',
      );
    }
    if (previous != null && edit.offset < previous.end) {
      throw SourceEditException(
        'Edit range ${edit.offset}..${edit.end} overlaps '
        '${previous.offset}..${previous.end}.',
      );
    }
    previous = edit;
  }
}
