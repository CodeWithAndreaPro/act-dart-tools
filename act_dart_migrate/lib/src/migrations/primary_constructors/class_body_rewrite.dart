part of 'primary_constructors.dart';

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
    final primaryBodyReplacementSource =
        primaryBodySource != null && _hasBodyMemberAfter(constructor)
        ? '$primaryBodySource\n'
        : primaryBodySource;
    validateSourceEdits(source, [
      for (final range in removalRanges) SourceEdit.delete(range),
    ]);
    final _ClassBodyRewritePlan plan;
    final allBodyMembersAreRemoved = _allBodyMembersAreRemoved(
      removableMembers,
    );
    if (primaryBodySource == null && allBodyMembersAreRemoved) {
      plan = _bodyContainsOnlyRemovedMemberSource(removalRanges)
          ? _ClassBodyRewritePlan(
              edits: const [],
              emptyBodyRewrite: _EmptyBodyRewriteIntent(body: declaration.body),
            )
          : _ClassBodyRewritePlan(
              edits: [
                for (final range in removalRanges) SourceEdit.delete(range),
              ],
              emptyBodySkipReason: DeclarationSkipReason.classBodyComment,
            );
    } else {
      plan = _ClassBodyRewritePlan(
        edits: [
          for (final range in removalRanges) SourceEdit.delete(range),
          if (primaryBodyReplacementSource != null)
            SourceEdit.replace(
              _memberRemovalRange(source, constructor),
              primaryBodyReplacementSource,
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

  bool _hasBodyMemberAfter(ClassMember member) {
    final members = declaration.body.members;
    for (var index = 0; index < members.length - 1; index++) {
      if (identical(members[index], member)) {
        return true;
      }
    }
    return false;
  }

  bool _bodyContainsOnlyRemovedMemberSource(List<SourceRange> removalRanges) {
    final bodyRange = _blockBodyContentRange(declaration.body);
    if (bodyRange == null) {
      return false;
    }
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

  bool _isWhitespaceRange(int start, int end) {
    return source.substring(start, end).trim().isEmpty;
  }
}
