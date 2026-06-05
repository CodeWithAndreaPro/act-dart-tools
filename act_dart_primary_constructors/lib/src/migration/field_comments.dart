part of '../migration.dart';

_FieldCommentMigration _fieldCommentMigration({
  required String source,
  required ClassDeclaration declaration,
  required FieldDeclaration member,
}) {
  if (_hasFollowingFieldComment(source, declaration, member)) {
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
      _isSharedOrdinaryFieldComment(source, declaration, member)) {
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
  ClassDeclaration declaration,
  FieldDeclaration member,
) {
  final nextMember = _nextClassMember(declaration, member);
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
  ClassDeclaration declaration,
  FieldDeclaration member,
) {
  final lineEnd = _lineEndOffset(source, member.end);
  if (_hasCommentMarker(source.substring(member.end, lineEnd))) {
    return true;
  }

  final nextMember = _nextClassMember(declaration, member);
  final nextOffset = nextMember == null
      ? declaration.body.end
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

ClassMember? _nextClassMember(
  ClassDeclaration declaration,
  ClassMember member,
) {
  final members = declaration.body.members;
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

_SourceRange _commentRange(List<Token> comments) {
  return _SourceRange(
    comments.first.offset,
    comments.last.end - comments.first.offset,
  );
}

_SourceRange _memberRemovalRange(String source, ClassMember member) {
  final leadingCommentRange = member is FieldDeclaration
      ? _directFieldLeadingCommentRange(source, member)
      : null;
  var start = leadingCommentRange?.offset ?? member.offset;
  while (start > 0 && source.codeUnitAt(start - 1) != 10) {
    start--;
  }

  var end = member.end;
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
  return _SourceRange(start, end - start);
}

_SourceRange? _directFieldLeadingCommentRange(
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
