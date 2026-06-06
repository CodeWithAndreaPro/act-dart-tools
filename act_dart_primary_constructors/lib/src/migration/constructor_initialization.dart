part of '../migration.dart';

final class _ConstructorRealizationPlanner {
  const _ConstructorRealizationPlanner({
    required this.source,
    required this.declaration,
    required this.constructor,
  });

  final String source;
  final ClassDeclaration declaration;
  final ConstructorDeclaration constructor;

  _ConstructorRealizationDecision decide() {
    final initializationDecision = _ConstructorInitializationPlanner(
      source: source,
      declaration: declaration,
      constructor: constructor,
    ).decide();
    final _ConstructorInitializationPlan initializationPlan;
    switch (initializationDecision) {
      case _PlannedConstructorInitialization(:final plan):
        initializationPlan = plan;
      case _SkippedConstructorInitialization(:final reason):
        return _SkippedConstructorRealization(reason);
    }

    final fieldToParameterDecision =
        _FieldToParameterPlanner(
          source: source,
          declaration: declaration,
          privateFieldInitializersByName:
              initializationPlan.privateFieldInitializersByName,
        ).decideConstructorParameters(
          parameters: constructor.parameters,
          fieldInitializers: initializationPlan.fieldInitializers,
        );
    final List<_ParameterMigrationPlan> parameterPlans;
    switch (fieldToParameterDecision) {
      case _PlannedFieldToParameter(
        parameterPlans: final plannedParameterPlans,
      ):
        parameterPlans = plannedParameterPlans;
      case _SkippedFieldToParameter(:final reason):
        return _SkippedConstructorRealization(reason);
    }

    return _PlannedConstructorRealization(
      _ConstructorRealizationPlan(
        parameterPlans: parameterPlans,
        fieldInitializerEdits: [
          for (final fieldInitializer in initializationPlan.fieldInitializers)
            SourceEdit.insert(
              fieldInitializer.variable.end,
              ' = ${_sourceFor(source, fieldInitializer.expression)}',
            ),
        ],
        primaryBodySource: initializationPlan.primaryBodySource,
      ),
    );
  }
}

sealed class _ConstructorRealizationDecision {
  const _ConstructorRealizationDecision();
}

final class _PlannedConstructorRealization
    extends _ConstructorRealizationDecision {
  const _PlannedConstructorRealization(this.plan);

  final _ConstructorRealizationPlan plan;
}

final class _SkippedConstructorRealization
    extends _ConstructorRealizationDecision {
  const _SkippedConstructorRealization(this.reason);

  final DeclarationSkipReason reason;
}

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
    final visitor = _FieldWriteVisitor(
      fieldNames,
      _constructorBodyLocalNames(),
    );
    body.accept(visitor);
    return visitor.hasFieldWrite;
  }

  Set<String> _constructorBodyLocalNames() {
    return {
      for (final parameter in constructor.parameters.parameters)
        ?_constructorBodyLocalParameterName(parameter),
    };
  }

  String? _constructorBodyLocalParameterName(FormalParameter parameter) {
    if (parameter is FieldFormalParameter) {
      return null;
    }
    return parameter.name?.lexeme;
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
  _FieldWriteVisitor(this.fieldNames, Set<String> initialLocalNames)
    : _scopes = [initialLocalNames];

  final Set<String> fieldNames;
  final List<Set<String>> _scopes;
  bool hasFieldWrite = false;

  @override
  void visitBlock(Block node) {
    _withScope(() {
      for (final statement in node.statements) {
        if (hasFieldWrite) {
          return;
        }
        statement.accept(this);
      }
    });
  }

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

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    _declare(node.functionDeclaration.name.lexeme);
    node.functionDeclaration.functionExpression.accept(this);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _withScope(() {
      _declareParameters(node.parameters);
      node.body.accept(this);
    });
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    _visitVariableDeclarations(node.variables);
  }

  @override
  void visitCatchClause(CatchClause node) {
    _withScope(() {
      if (node.exceptionParameter case final exceptionParameter?) {
        _declare(exceptionParameter.name.lexeme);
      }
      if (node.stackTraceParameter case final stackTraceParameter?) {
        _declare(stackTraceParameter.name.lexeme);
      }
      node.body.accept(this);
    });
  }

  @override
  void visitForElement(ForElement node) {
    _visitForLoop(node.forLoopParts, node.body);
  }

  @override
  void visitForStatement(ForStatement node) {
    _visitForLoop(node.forLoopParts, node.body);
  }

  void _checkWriteTarget(Expression target) {
    final fieldName = _fieldWriteTargetName(target);
    if (fieldName != null &&
        fieldNames.contains(fieldName) &&
        (_isExplicitThisTarget(target) || !_isLocalName(fieldName))) {
      hasFieldWrite = true;
    }
  }

  String? _fieldWriteTargetName(Expression target) {
    target = _unparenthesized(target);
    if (target is SimpleIdentifier) {
      return target.token.lexeme;
    }
    if (target is PrefixedIdentifier && target.prefix.token.lexeme == 'this') {
      return target.identifier.token.lexeme;
    }
    if (target is PropertyAccess && target.target is ThisExpression) {
      return target.propertyName.token.lexeme;
    }
    return null;
  }

  bool _isExplicitThisTarget(Expression target) {
    target = _unparenthesized(target);
    if (target is PrefixedIdentifier && target.prefix.token.lexeme == 'this') {
      return true;
    }
    return target is PropertyAccess && target.target is ThisExpression;
  }

  Expression _unparenthesized(Expression target) {
    while (target is ParenthesizedExpression) {
      target = target.expression;
    }
    return target;
  }

  void _visitVariableDeclarations(VariableDeclarationList variables) {
    for (final variable in variables.variables) {
      variable.initializer?.accept(this);
      _declare(variable.name.lexeme);
      if (hasFieldWrite) {
        return;
      }
    }
  }

  void _visitForLoop(ForLoopParts forLoopParts, AstNode body) {
    _withScope(() {
      _visitForLoopParts(forLoopParts);
      if (!hasFieldWrite) {
        body.accept(this);
      }
    });
  }

  void _visitForLoopParts(ForLoopParts parts) {
    switch (parts) {
      case ForPartsWithDeclarations(:final variables):
        _visitVariableDeclarations(variables);
        _visitForPartsRemainder(parts);
      case ForPartsWithExpression(:final initialization):
        initialization?.accept(this);
        _visitForPartsRemainder(parts);
      case ForPartsWithPattern():
        _visitForPartsRemainder(parts);
      case ForEachPartsWithDeclaration(:final loopVariable):
        parts.iterable.accept(this);
        _declare(loopVariable.name.lexeme);
      case ForEachPartsWithIdentifier(:final identifier):
        parts.iterable.accept(this);
        _checkWriteTarget(identifier);
      case ForEachPartsWithPattern():
        parts.iterable.accept(this);
    }
  }

  void _visitForPartsRemainder(ForParts parts) {
    if (hasFieldWrite) {
      return;
    }
    parts.condition?.accept(this);
    for (final updater in parts.updaters) {
      if (hasFieldWrite) {
        return;
      }
      updater.accept(this);
    }
  }

  void _declareParameters(FormalParameterList? parameters) {
    if (parameters == null) {
      return;
    }
    for (final parameter in parameters.parameters) {
      if (parameter is FieldFormalParameter) {
        continue;
      }
      if (parameter.name case final name?) {
        _declare(name.lexeme);
      }
    }
  }

  void _declare(String name) {
    _scopes.last.add(name);
  }

  bool _isLocalName(String name) {
    for (final scope in _scopes.reversed) {
      if (scope.contains(name)) {
        return true;
      }
    }
    return false;
  }

  void _withScope(void Function() run) {
    _scopes.add(<String>{});
    try {
      run();
    } finally {
      _scopes.removeLast();
    }
  }
}
