part of 'primary_constructors.dart';

_FieldCommentMigration _fieldCommentMigration({
  required String source,
  required _DeclarationBodyInfo bodyInfo,
  required FieldDeclaration member,
}) {
  if (_hasFollowingFieldComment(source, bodyInfo, member)) {
    return const _FieldCommentMigration.ambiguous();
  }
  if (_hasInlineFieldComment(source, member)) {
    return const _FieldCommentMigration.ambiguous();
  }

  final comments = _leadingCommentTokens(member);
  if (comments.isEmpty) {
    return const _FieldCommentMigration.none();
  }
  if (!_isDirectCommentCluster(
    source,
    comments,
    member.firstTokenAfterCommentAndMetadata.offset,
  )) {
    return const _FieldCommentMigration.ambiguous();
  }

  final documentationComment =
      member.documentationComment ?? member.fields.documentationComment;
  if (documentationComment != null) {
    final documentationTokens = documentationComment.tokens;
    if (!_sameCommentTokens(comments, documentationTokens)) {
      return const _FieldCommentMigration.ambiguous();
    }
    return _FieldCommentMigration.direct(
      source: _commentSource(source, comments),
    );
  }

  if (!_isOrdinaryCommentCluster(comments) ||
      _isSharedOrdinaryFieldComment(source, bodyInfo, member)) {
    return const _FieldCommentMigration.ambiguous();
  }
  return _FieldCommentMigration.direct(
    source: _commentSource(source, comments),
  );
}

List<Token> _leadingCommentTokens(AnnotatedNode node) {
  final comments = <Token>[];
  CommentToken? comment =
      node.firstTokenAfterCommentAndMetadata.precedingComments;
  while (comment != null) {
    comments.add(comment);
    comment = comment.next as CommentToken?;
  }
  return comments;
}

bool _sameCommentTokens(List<Token> left, List<Token> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index].offset != right[index].offset ||
        left[index].end != right[index].end) {
      return false;
    }
  }
  return true;
}

bool _isDirectCommentCluster(
  String source,
  List<Token> comments,
  int targetOffset,
) {
  for (var index = 0; index < comments.length - 1; index++) {
    if (!_hasSingleLineWhitespaceGap(
      source,
      comments[index].end,
      comments[index + 1].offset,
    )) {
      return false;
    }
  }
  return _hasSingleLineWhitespaceGap(source, comments.last.end, targetOffset);
}

bool _hasSingleLineWhitespaceGap(String source, int start, int end) {
  final gap = source.substring(start, end);
  return gap.trim().isEmpty && _lineBreakCount(gap) == 1;
}

int _lineBreakCount(String source) {
  var count = 0;
  for (var index = 0; index < source.length; index++) {
    if (source.codeUnitAt(index) == 10) {
      count++;
    }
  }
  return count;
}

bool _isOrdinaryCommentCluster(List<Token> comments) {
  if (comments.first.type == TokenType.SINGLE_LINE_COMMENT) {
    return comments.every(
      (comment) =>
          comment.type == TokenType.SINGLE_LINE_COMMENT &&
          !comment.lexeme.startsWith('///'),
    );
  }
  if (comments.first.type == TokenType.MULTI_LINE_COMMENT) {
    return comments.length == 1 && !comments.first.lexeme.startsWith('/**');
  }
  return false;
}

bool _isSharedOrdinaryFieldComment(
  String source,
  _DeclarationBodyInfo bodyInfo,
  FieldDeclaration member,
) {
  final nextMember = _nextBodyMember(bodyInfo, member);
  if (nextMember is! FieldDeclaration ||
      _hasBlankLineBetween(source, member.end, nextMember.offset)) {
    return false;
  }
  final nextComments = _leadingCommentTokens(nextMember);
  return nextComments.isEmpty ||
      !_isDirectCommentCluster(
        source,
        nextComments,
        nextMember.firstTokenAfterCommentAndMetadata.offset,
      );
}

bool _hasFollowingFieldComment(
  String source,
  _DeclarationBodyInfo bodyInfo,
  FieldDeclaration member,
) {
  final lineEnd = _lineEndOffset(source, member.end);
  if (_hasCommentMarker(source.substring(member.end, lineEnd))) {
    return true;
  }

  final nextMember = _nextBodyMember(bodyInfo, member);
  final nextOffset = nextMember == null
      ? bodyInfo.bodyEnd
      : _memberLeadingCommentOffset(nextMember);
  if (_hasCommentMarker(source.substring(lineEnd, nextOffset))) {
    return true;
  }

  if (nextMember is FieldDeclaration) {
    return false;
  }
  return nextMember != null &&
      _leadingCommentTokens(nextMember).any(_isOrdinaryCommentToken);
}

bool _hasInlineFieldComment(String source, FieldDeclaration member) {
  final fieldSource = source.substring(
    member.firstTokenAfterCommentAndMetadata.offset,
    member.end,
  );
  return _hasCommentMarker(fieldSource);
}

int _memberLeadingCommentOffset(ClassMember member) {
  final comments = _leadingCommentTokens(member);
  if (comments.isNotEmpty) {
    return comments.first.offset;
  }
  return member.offset;
}

bool _isOrdinaryCommentToken(Token comment) {
  return switch (comment.type) {
    TokenType.SINGLE_LINE_COMMENT => !comment.lexeme.startsWith('///'),
    TokenType.MULTI_LINE_COMMENT => !comment.lexeme.startsWith('/**'),
    _ => false,
  };
}

int _lineEndOffset(String source, int offset) {
  final lineEnd = source.indexOf('\n', offset);
  return lineEnd == -1 ? source.length : lineEnd;
}

bool _hasCommentMarker(String source) {
  return source.contains('//') || source.contains('/*');
}

bool _hasBlankLineBetween(String source, int start, int end) {
  return RegExp(r'\n[ \t\r]*\n').hasMatch(source.substring(start, end));
}

ClassMember? _nextBodyMember(
  _DeclarationBodyInfo bodyInfo,
  ClassMember member,
) {
  final members = bodyInfo.members;
  for (var index = 0; index < members.length - 1; index++) {
    if (identical(members[index], member)) {
      return members[index + 1];
    }
  }
  return null;
}

String _commentSource(String source, List<Token> comments) {
  return source.substring(comments.first.offset, comments.last.end);
}

SourceRange _commentRange(List<Token> comments) {
  return SourceRange.fromStartEnd(
    start: comments.first.offset,
    end: comments.last.end,
  );
}

SourceRange _memberRemovalRange(String source, ClassMember member) {
  final leadingCommentRange = member is FieldDeclaration
      ? _directFieldLeadingCommentRange(source, member)
      : null;
  final memberRange = member is FieldDeclaration && leadingCommentRange != null
      ? SourceRange.fromStartEnd(
          start: member.firstTokenAfterCommentAndMetadata.offset,
          end: member.end,
        )
      : _rangeFor(member);
  return sourceLineRemovalRange(
    source,
    memberRange,
    leadingRange: leadingCommentRange,
  );
}

SourceRange? _directFieldLeadingCommentRange(
  String source,
  FieldDeclaration member,
) {
  final comments = _leadingCommentTokens(member);
  if (comments.isEmpty ||
      !_isDirectCommentCluster(
        source,
        comments,
        member.firstTokenAfterCommentAndMetadata.offset,
      )) {
    return null;
  }
  return _commentRange(comments);
}
