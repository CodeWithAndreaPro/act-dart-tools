part of '../migration.dart';

_ConstructorInitializerClassification _classifyConstructorInitializers({
  required String source,
  required ClassDeclaration declaration,
  required ConstructorDeclaration constructor,
  required Set<String> parameterNames,
}) {
  final privateFieldInitializersByName = <String, String>{};
  final fieldInitializers = <_FieldInitializerMigration>[];
  final retainedInitializers = <ConstructorInitializer>[];
  final initializedFieldNames = <String>{};

  for (final initializer in constructor.initializers) {
    if (initializer is RedirectingConstructorInvocation) {
      return const _ConstructorInitializerClassification.skip(
        DeclarationSkipReason.redirectingConstructor,
      );
    }
    if (initializer is SuperConstructorInvocation) {
      if (initializer.constructorName != null) {
        return const _ConstructorInitializerClassification.skip(
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
      return const _ConstructorInitializerClassification.skip(
        DeclarationSkipReason.unsupportedInitializer,
      );
    }

    final fieldName = initializer.fieldName.token.lexeme;
    final expression = initializer.expression;
    if (fieldName.startsWith('_') && expression is SimpleIdentifier) {
      if (privateFieldInitializersByName.containsKey(fieldName)) {
        return const _ConstructorInitializerClassification.skip(
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
      return _ConstructorInitializerClassification.skip(fieldSkipReason);
    }
    if (!_dependsOnlyOnConstructorParameters(expression, parameterNames)) {
      return const _ConstructorInitializerClassification.skip(
        DeclarationSkipReason.unsafeInitializerDependency,
      );
    }
    if (!initializedFieldNames.add(fieldName)) {
      return const _ConstructorInitializerClassification.skip(
        DeclarationSkipReason.unsupportedInitializer,
      );
    }
    final field = _fieldDeclarationFor(declaration, fieldName);
    if (field == null) {
      return const _ConstructorInitializerClassification.skip(
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

  return _ConstructorInitializerClassification.plan(
    _ConstructorInitializerPlan(
      privateFieldInitializersByName: privateFieldInitializersByName,
      fieldInitializers: fieldInitializers,
      retainedInitializers: retainedInitializers,
    ),
  );
}

Set<String> _constructorParameterNames(ConstructorDeclaration constructor) {
  return {
    for (final parameter in constructor.parameters.parameters)
      if (parameter.name case final name?) name.lexeme,
  };
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
