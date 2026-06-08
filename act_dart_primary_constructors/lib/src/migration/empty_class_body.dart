part of '../migration.dart';

final class _EmptyClassBodyPlanner {
  const _EmptyClassBodyPlanner({
    required this.source,
    required this.declaration,
  });

  final String source;
  final ClassDeclaration declaration;

  _EmptyClassBodyDecision decide() {
    if (!_isOrdinaryClassDeclaration(declaration) ||
        declaration.namePart is PrimaryConstructorDeclaration ||
        declaration.body.members.isNotEmpty) {
      return const _NoOpEmptyClassBody();
    }

    final bodyRange = _blockClassBodyContentRange(declaration.body);
    if (bodyRange == null) {
      return const _NoOpEmptyClassBody();
    }

    if (_bodyContainsOnlyWhitespace(bodyRange)) {
      return _MigratedEmptyClassBody(
        _EmptyClassBodyRewriteIntent(declaration: declaration),
      );
    }

    return const _SkippedEmptyClassBody(DeclarationSkipReason.classBodyComment);
  }

  bool _bodyContainsOnlyWhitespace(SourceRange bodyRange) {
    return source.substring(bodyRange.offset, bodyRange.end).trim().isEmpty;
  }
}

sealed class _EmptyClassBodyDecision {
  const _EmptyClassBodyDecision();
}

final class _MigratedEmptyClassBody extends _EmptyClassBodyDecision {
  const _MigratedEmptyClassBody(this.rewrite);

  final _EmptyClassBodyRewriteIntent rewrite;
}

final class _SkippedEmptyClassBody extends _EmptyClassBodyDecision {
  const _SkippedEmptyClassBody(this.reason);

  final DeclarationSkipReason reason;
}

final class _NoOpEmptyClassBody extends _EmptyClassBodyDecision {
  const _NoOpEmptyClassBody();
}

bool _isOrdinaryClassDeclaration(ClassDeclaration declaration) {
  return declaration.mixinKeyword == null;
}
