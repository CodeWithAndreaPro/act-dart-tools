class SourceRange {
  const SourceRange({required this.offset, required this.length});

  SourceRange.fromStartEnd({required int start, required int end})
    : offset = start,
      length = end - start;

  final int offset;
  final int length;

  int get end => offset + length;
}

class SourceEdit {
  const SourceEdit({
    required this.offset,
    required this.length,
    required this.replacement,
  });

  const SourceEdit.insert(int offset, String replacement)
    : this(offset: offset, length: 0, replacement: replacement);

  SourceEdit.replace(SourceRange range, this.replacement)
    : offset = range.offset,
      length = range.length;

  SourceEdit.delete(SourceRange range) : this.replace(range, '');

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
  final orderedEdits = _indexedEdits(edits)
    ..sort((a, b) {
      final byOffset = b.edit.offset.compareTo(a.edit.offset);
      if (byOffset != 0) {
        return byOffset;
      }
      final byLength = b.edit.length.compareTo(a.edit.length);
      if (byLength != 0) {
        return byLength;
      }
      return b.index.compareTo(a.index);
    });

  var result = source;
  for (final indexedEdit in orderedEdits) {
    final edit = indexedEdit.edit;
    result = result.replaceRange(edit.offset, edit.end, edit.replacement);
  }
  return result;
}

void validateSourceEdits(String source, List<SourceEdit> edits) {
  final orderedEdits = _indexedEdits(edits)
    ..sort((a, b) {
      final byOffset = a.edit.offset.compareTo(b.edit.offset);
      if (byOffset != 0) {
        return byOffset;
      }
      final byLength = a.edit.length.compareTo(b.edit.length);
      if (byLength != 0) {
        return byLength;
      }
      return a.index.compareTo(b.index);
    });
  SourceEdit? previous;
  for (final indexedEdit in orderedEdits) {
    final edit = indexedEdit.edit;
    if (edit.offset < 0 || edit.offset > source.length) {
      throw SourceEditException(
        'Edit offset ${edit.offset} is outside source bounds 0..${source.length}.',
      );
    }
    if (edit.length < 0) {
      throw SourceEditException('Edit length ${edit.length} is negative.');
    }
    if (edit.end > source.length) {
      throw SourceEditException(
        'Edit range ${edit.offset}..${edit.end} is outside source bounds '
        '0..${source.length}.',
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

List<({SourceEdit edit, int index})> _indexedEdits(List<SourceEdit> edits) {
  return [
    for (var index = 0; index < edits.length; index++)
      (edit: edits[index], index: index),
  ];
}
