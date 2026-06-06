part of '../migration.dart';

final class _ConstructorInitializationPlanner {
  const _ConstructorInitializationPlanner({
    required this.source,
    required this.declaration,
    required this.constructor,
  });

  final String source;
  final ClassDeclaration declaration;
  final ConstructorDeclaration constructor;

  _ConstructorInitializationDecision decide() {
    final bodySkipReason = _bodySkipReason();
    if (bodySkipReason != null) {
      return _SkippedConstructorInitialization(bodySkipReason);
    }

    final privateFieldInitializersByName = <String, String>{};
    final fieldInitializers = <_FieldInitializerMigration>[];
    final retainedInitializers = <ConstructorInitializer>[];
    final initializedFieldNames = <String>{};
    final parameterNames = _constructorParameterNames();

    for (final initializer in constructor.initializers) {
      if (initializer is RedirectingConstructorInvocation) {
        return const _SkippedConstructorInitialization(
          DeclarationSkipReason.redirectingConstructor,
        );
      }
      if (initializer is SuperConstructorInvocation) {
        if (initializer.constructorName != null) {
          return const _SkippedConstructorInitialization(
            DeclarationSkipReason.namedSuperInitializer,
          );
        }
        retainedInitializers.add(initializer);
        continue;
      }
      if (initializer is AssertInitializer) {
        retainedInitializers.add(initializer);
        continue;
      }
      if (initializer is! ConstructorFieldInitializer) {
        return const _SkippedConstructorInitialization(
          DeclarationSkipReason.unsupportedInitializer,
        );
      }

      final fieldName = initializer.fieldName.token.lexeme;
      final expression = initializer.expression;
      if (fieldName.startsWith('_') && expression is SimpleIdentifier) {
        if (privateFieldInitializersByName.containsKey(fieldName)) {
          return const _SkippedConstructorInitialization(
            DeclarationSkipReason.unsupportedInitializer,
          );
        }
        privateFieldInitializersByName[fieldName] = expression.token.lexeme;
        continue;
      }

      final fieldSkipReason = _mappedFieldSkipReason(
        source: source,
        declaration: declaration,
        fieldName: fieldName,
      );
      if (fieldSkipReason != null) {
        return _SkippedConstructorInitialization(fieldSkipReason);
      }
      if (!_dependsOnlyOnConstructorParameters(expression, parameterNames)) {
        return const _SkippedConstructorInitialization(
          DeclarationSkipReason.unsafeInitializerDependency,
        );
      }
      if (!initializedFieldNames.add(fieldName)) {
        return const _SkippedConstructorInitialization(
          DeclarationSkipReason.unsupportedInitializer,
        );
      }
      final field = _fieldDeclarationFor(declaration, fieldName);
      if (field == null) {
        return const _SkippedConstructorInitialization(
          DeclarationSkipReason.missingField,
        );
      }
      fieldInitializers.add(
        _FieldInitializerMigration(
          fieldName: fieldName,
          variable: field.$3,
          expression: expression,
        ),
      );
    }

    return _PlannedConstructorInitialization(
      _ConstructorInitializationPlan(
        privateFieldInitializersByName: privateFieldInitializersByName,
        fieldInitializers: fieldInitializers,
        primaryBodySource: _primaryBodySource(retainedInitializers),
      ),
    );
  }

  DeclarationSkipReason? _bodySkipReason() {
    final body = constructor.body;
    if (body is EmptyFunctionBody) {
      return null;
    }
    if (body is! BlockFunctionBody ||
        body.keyword != null ||
        body.star != null ||
        constructor.constKeyword != null) {
      return DeclarationSkipReason.unsupportedConstructorBody;
    }
    if (_bodyWritesInstanceField(body)) {
      return DeclarationSkipReason.fieldInitializingConstructorBody;
    }
    return null;
  }

  bool _bodyWritesInstanceField(BlockFunctionBody body) {
    final fieldNames = {
      for (final member
          in declaration.body.members.whereType<FieldDeclaration>())
        if (!member.isStatic)
          for (final variable in member.fields.variables) variable.name.lexeme,
    };
    if (fieldNames.isEmpty) {
      return false;
    }
    final visitor = _FieldWriteVisitor(fieldNames);
    body.accept(visitor);
    return visitor.hasFieldWrite;
  }

  String? _primaryBodySource(
    List<ConstructorInitializer> retainedInitializers,
  ) {
    final body = constructor.body;
    if (retainedInitializers.isEmpty && body is! BlockFunctionBody) {
      return null;
    }
    final indent = _lineIndentation(source, constructor.offset);
    final initializerSource = retainedInitializers.isEmpty
        ? ''
        : ' : ${retainedInitializers.map((initializer) => _sourceFor(source, initializer)).join(', ')}';
    final bodySource = body is BlockFunctionBody
        ? ' ${_sourceFor(source, body)}'
        : ';';
    return '${indent}this$initializerSource$bodySource\n';
  }

  Set<String> _constructorParameterNames() {
    return {
      for (final parameter in constructor.parameters.parameters)
        if (parameter.name case final name?) name.lexeme,
    };
  }
}

sealed class _ConstructorInitializationDecision {
  const _ConstructorInitializationDecision();
}

final class _PlannedConstructorInitialization
    extends _ConstructorInitializationDecision {
  const _PlannedConstructorInitialization(this.plan);

  final _ConstructorInitializationPlan plan;
}

final class _SkippedConstructorInitialization
    extends _ConstructorInitializationDecision {
  const _SkippedConstructorInitialization(this.reason);

  final DeclarationSkipReason reason;
}

bool _dependsOnlyOnConstructorParameters(
  Expression expression,
  Set<String> parameterNames,
) {
  final visitor = _ParameterOnlyExpressionVisitor(parameterNames);
  expression.accept(visitor);
  return visitor.isSafe;
}

class _ParameterOnlyExpressionVisitor extends RecursiveAstVisitor<void> {
  _ParameterOnlyExpressionVisitor(this.parameterNames);

  final Set<String> parameterNames;
  bool isSafe = true;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!isSafe || _isNonReferenceIdentifier(node)) {
      return;
    }
    if (!parameterNames.contains(node.token.lexeme)) {
      isSafe = false;
    }
  }

  @override
  void visitSuperExpression(SuperExpression node) {
    isSafe = false;
  }

  @override
  void visitThisExpression(ThisExpression node) {
    isSafe = false;
  }

  bool _isNonReferenceIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    if (parent is PrefixedIdentifier && identical(parent.identifier, node)) {
      return true;
    }
    if (parent is PropertyAccess && identical(parent.propertyName, node)) {
      return true;
    }
    if (parent is MethodInvocation &&
        identical(parent.methodName, node) &&
        parent.target != null) {
      return true;
    }
    return false;
  }
}

class _FieldWriteVisitor extends RecursiveAstVisitor<void> {
  _FieldWriteVisitor(this.fieldNames);

  final Set<String> fieldNames;
  bool hasFieldWrite = false;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _checkWriteTarget(node.leftHandSide);
    if (!hasFieldWrite) {
      super.visitAssignmentExpression(node);
    }
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.lexeme == '++' || node.operator.lexeme == '--') {
      _checkWriteTarget(node.operand);
    }
    if (!hasFieldWrite) {
      super.visitPostfixExpression(node);
    }
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.operator.lexeme == '++' || node.operator.lexeme == '--') {
      _checkWriteTarget(node.operand);
    }
    if (!hasFieldWrite) {
      super.visitPrefixExpression(node);
    }
  }

  void _checkWriteTarget(Expression target) {
    final fieldName = _fieldWriteTargetName(target);
    if (fieldName != null && fieldNames.contains(fieldName)) {
      hasFieldWrite = true;
    }
  }

  String? _fieldWriteTargetName(Expression target) {
    if (target is SimpleIdentifier) {
      return target.token.lexeme;
    }
    if (target is PrefixedIdentifier && target.prefix.token.lexeme == 'this') {
      return target.identifier.token.lexeme;
    }
    if (target is PropertyAccess && target.target is ThisExpression) {
      return target.propertyName.token.lexeme;
    }
    if (target is ParenthesizedExpression) {
      return _fieldWriteTargetName(target.expression);
    }
    return null;
  }
}
