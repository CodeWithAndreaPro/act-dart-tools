part of 'primary_constructors.dart';

final class _EmptyBodyPlanner {
  const _EmptyBodyPlanner({required this.source, required this.body});

  final String source;
  final AstNode body;

  _EmptyClassBodyDecision decide() {
    if (!_hasEmptyBodyMembers(body)) {
      return const _NoOpEmptyClassBody();
    }

    final bodyRange = _blockBodyContentRange(body);
    if (bodyRange == null) {
      return const _NoOpEmptyClassBody();
    }

    if (_bodyContainsOnlyWhitespace(bodyRange)) {
      return _MigratedEmptyClassBody(_EmptyBodyRewriteIntent(body: body));
    }

    return const _SkippedEmptyClassBody(DeclarationSkipReason.classBodyComment);
  }

  bool _bodyContainsOnlyWhitespace(SourceRange bodyRange) {
    return source.substring(bodyRange.offset, bodyRange.end).trim().isEmpty;
  }

  bool _hasEmptyBodyMembers(AstNode body) {
    return switch (body) {
      ClassBody(:final members) => members.isEmpty,
      EnumBody(:final constants, :final members) =>
        constants.isEmpty && members.isEmpty,
      _ => false,
    };
  }
}

sealed class _EmptyClassBodyDecision {
  const _EmptyClassBodyDecision();
}

final class _MigratedEmptyClassBody extends _EmptyClassBodyDecision {
  const _MigratedEmptyClassBody(this.rewrite);

  final _EmptyBodyRewriteIntent rewrite;
}

final class _SkippedEmptyClassBody extends _EmptyClassBodyDecision {
  const _SkippedEmptyClassBody(this.reason);

  final DeclarationSkipReason reason;
}

final class _NoOpEmptyClassBody extends _EmptyClassBodyDecision {
  const _NoOpEmptyClassBody();
}
