part of '../migration.dart';

DeclarationSkipReason? _constructorBodySkipReason({
  required ClassDeclaration declaration,
  required ConstructorDeclaration constructor,
}) {
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
  if (_bodyWritesInstanceField(declaration: declaration, body: body)) {
    return DeclarationSkipReason.fieldInitializingConstructorBody;
  }
  return null;
}

bool _isSupportedConstructorBodyShape(FunctionBody body) {
  return body is EmptyFunctionBody || body is BlockFunctionBody;
}

bool _bodyWritesInstanceField({
  required ClassDeclaration declaration,
  required BlockFunctionBody body,
}) {
  final fieldNames = {
    for (final member in declaration.body.members.whereType<FieldDeclaration>())
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
