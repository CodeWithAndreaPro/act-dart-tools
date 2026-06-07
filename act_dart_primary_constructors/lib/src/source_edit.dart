class SourceRange {
  const SourceRange({required this.offset, required this.length});

  SourceRange.fromStartEnd({required int start, required int end})
    : offset = start,
      length = end - start;

  final int offset;
  final int length;

  int get end => offset + length;

  SourceRange relativeTo(SourceRange parent) {
    _validateRangeWithinParent(this, parent);
    return SourceRange(offset: offset - parent.offset, length: length);
  }

  SourceRange absoluteFrom(SourceRange parent) {
    _validateNestedRange(this, parent);
    return SourceRange(offset: parent.offset + offset, length: length);
  }
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

  SourceEdit relativeTo(SourceRange parent) {
    final range = SourceRange(
      offset: offset,
      length: length,
    ).relativeTo(parent);
    return SourceEdit(
      offset: range.offset,
      length: range.length,
      replacement: replacement,
    );
  }

  SourceEdit absoluteFrom(SourceRange parent) {
    final range = SourceRange(
      offset: offset,
      length: length,
    ).absoluteFrom(parent);
    return SourceEdit(
      offset: range.offset,
      length: range.length,
      replacement: replacement,
    );
  }
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

String applySourceEditsInRange(
  String source,
  SourceRange range,
  List<SourceEdit> edits,
) {
  validateSourceRange(source, range);
  final nestedSource = source.substring(range.offset, range.end);
  return applySourceEdits(nestedSource, [
    for (final edit in edits) edit.relativeTo(range),
  ]);
}

SourceRange sourceLineRemovalRange(
  String source,
  SourceRange range, {
  SourceRange? leadingRange,
}) {
  validateSourceRange(source, range);
  if (leadingRange case final leadingRange?) {
    validateSourceRange(source, leadingRange);
    if (leadingRange.end > range.offset) {
      throw SourceEditException(
        'Leading range ${leadingRange.offset}..${leadingRange.end} overlaps '
        'removal range ${range.offset}..${range.end}.',
      );
    }
  }

  var start = leadingRange?.offset ?? range.offset;
  while (start > 0 && source.codeUnitAt(start - 1) != 10) {
    start--;
  }

  var end = range.end;
  while (end < source.length && source.codeUnitAt(end) != 10) {
    end++;
  }
  if (end < source.length) {
    end++;
  }
  while (end < source.length) {
    final nextLineEnd = source.indexOf('\n', end);
    final lineEnd = nextLineEnd == -1 ? source.length : nextLineEnd;
    if (source.substring(end, lineEnd).trim().isNotEmpty) {
      break;
    }
    end = lineEnd == source.length ? lineEnd : lineEnd + 1;
  }
  return SourceRange.fromStartEnd(start: start, end: end);
}

void validateSourceRange(String source, SourceRange range) {
  if (range.offset < 0 || range.offset > source.length) {
    throw SourceEditException(
      'Source range offset ${range.offset} is outside source bounds '
      '0..${source.length}.',
    );
  }
  if (range.length < 0) {
    throw SourceEditException(
      'Source range length ${range.length} is negative.',
    );
  }
  if (range.end > source.length) {
    throw SourceEditException(
      'Source range ${range.offset}..${range.end} is outside source bounds '
      '0..${source.length}.',
    );
  }
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

void _validateRangeWithinParent(SourceRange range, SourceRange parent) {
  _validateRangeLengths(range, parent);
  if (range.offset < parent.offset || range.end > parent.end) {
    throw SourceEditException(
      'Range ${range.offset}..${range.end} is outside parent range '
      '${parent.offset}..${parent.end}.',
    );
  }
}

void _validateNestedRange(SourceRange range, SourceRange parent) {
  _validateRangeLengths(range, parent);
  if (range.offset < 0 || range.end > parent.length) {
    throw SourceEditException(
      'Nested range ${range.offset}..${range.end} is outside parent range '
      '0..${parent.length}.',
    );
  }
}

void _validateRangeLengths(SourceRange range, SourceRange parent) {
  if (range.length < 0) {
    throw SourceEditException('Range length ${range.length} is negative.');
  }
  if (parent.length < 0) {
    throw SourceEditException(
      'Parent range length ${parent.length} is negative.',
    );
  }
}
