part of '../migration.dart';

final class _ClassBodyRewritePlanner {
  const _ClassBodyRewritePlanner({
    required this.source,
    required this.declaration,
    required this.constructor,
  });

  final String source;
  final ClassDeclaration declaration;
  final ConstructorDeclaration constructor;

  _ClassBodyRewritePlan plan({
    required Set<ClassMember> removableMembers,
    required String? primaryBodySource,
  }) {
    final removalRanges = [
      for (final member in removableMembers)
        _memberRemovalRange(source, member),
    ];
    validateSourceEdits(source, [
      for (final range in removalRanges) SourceEdit.delete(range),
    ]);
    final _ClassBodyRewritePlan plan;
    if (primaryBodySource == null &&
        _allBodyMembersAreRemoved(removableMembers) &&
        _bodyContainsOnlyRemovedMemberSource(removalRanges)) {
      plan = _ClassBodyRewritePlan(
        edits: const [],
        emptyClassBodyRewrite: _EmptyClassBodyRewriteIntent(
          declaration: declaration,
        ),
      );
    } else {
      plan = _ClassBodyRewritePlan(
        edits: [
          for (final range in removalRanges) SourceEdit.delete(range),
          if (primaryBodySource != null)
            SourceEdit.replace(
              _memberRemovalRange(source, constructor),
              primaryBodySource,
            ),
        ],
      );
    }
    validateSourceEdits(source, plan.sourceEdits);
    return plan;
  }

  bool _allBodyMembersAreRemoved(Set<ClassMember> removableMembers) {
    return declaration.body.members.length == removableMembers.length &&
        declaration.body.members.every(removableMembers.contains);
  }

  bool _bodyContainsOnlyRemovedMemberSource(List<SourceRange> removalRanges) {
    final bodyRange = _ordinaryClassBodyContentRange();
    final sortedRanges = [...removalRanges]
      ..sort((a, b) => a.offset.compareTo(b.offset));
    var cursor = bodyRange.offset;
    for (final range in sortedRanges) {
      final start = range.offset < bodyRange.offset
          ? bodyRange.offset
          : range.offset;
      final end = range.end > bodyRange.end ? bodyRange.end : range.end;
      if (end <= bodyRange.offset || start >= bodyRange.end) {
        continue;
      }
      if (!_isWhitespaceRange(cursor, start)) {
        return false;
      }
      if (end > cursor) {
        cursor = end;
      }
    }
    return _isWhitespaceRange(cursor, bodyRange.end);
  }

  SourceRange _ordinaryClassBodyContentRange() {
    return SourceRange.fromStartEnd(
      start: declaration.body.offset + 1,
      end: declaration.body.end - 1,
    );
  }

  bool _isWhitespaceRange(int start, int end) {
    return source.substring(start, end).trim().isEmpty;
  }
}
