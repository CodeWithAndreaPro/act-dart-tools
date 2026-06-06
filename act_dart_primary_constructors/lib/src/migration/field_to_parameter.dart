part of '../migration.dart';

final class _FieldToParameterPlanner {
  _FieldToParameterPlanner({
    required this.source,
    required this.declaration,
    required this.privateFieldInitializersByName,
    required this.parametersOffset,
  });

  final String source;
  final ClassDeclaration declaration;
  final Map<String, String> privateFieldInitializersByName;
  final int parametersOffset;
  final Set<String> _usedFieldNames = <String>{};
  final Set<String> _usedPrivateInitializers = <String>{};

  bool get hasUnusedPrivateFieldInitializers {
    return _usedPrivateInitializers.length !=
        privateFieldInitializersByName.length;
  }

  bool usesField(String fieldName) => _usedFieldNames.contains(fieldName);

  _ConstructorParameterDecision decide(FormalParameter parameter) {
    if (parameter.metadata.isNotEmpty) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.parameterMetadata,
      );
    }

    if (parameter is FieldFormalParameter) {
      return _decideFieldFormalParameter(parameter);
    }

    if (parameter is RegularFormalParameter) {
      return _decidePrivateNamedFieldParameter(parameter);
    }

    return const _SkippedConstructorParameter(
      DeclarationSkipReason.unsupportedParameterShape,
    );
  }

  _ConstructorParameterDecision _decideFieldFormalParameter(
    FieldFormalParameter parameter,
  ) {
    if (!_isSimpleFieldFormalParameter(parameter)) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    final fieldName = parameter.name.lexeme;
    final fieldClassification = _classifyMappedField(fieldName);
    if (fieldClassification.skipReason case final reason?) {
      return _SkippedConstructorParameter(reason);
    }

    final field = fieldClassification.field!;
    return _planMappedFieldParameter(
      field: field,
      fieldName: fieldName,
      parameterOffset: parameter.offset,
      replacementOffset: field.leadingCommentSource != null
          ? parameter.offset
          : parameter.thisKeyword.offset,
      replacementEnd: parameter.name.end,
    );
  }

  _ConstructorParameterDecision _decidePrivateNamedFieldParameter(
    RegularFormalParameter parameter,
  ) {
    if (!_isSimpleRegularFormalParameter(parameter)) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    final parameterName = parameter.name?.lexeme;
    final parameterType = parameter.type;
    if (parameterName == null ||
        parameterName.startsWith('_') ||
        parameterType == null ||
        !parameter.isNamed) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    final fieldName = '_$parameterName';
    if (privateFieldInitializersByName[fieldName] != parameterName) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    final fieldClassification = _classifyMappedField(fieldName);
    if (fieldClassification.skipReason case final reason?) {
      return _SkippedConstructorParameter(reason);
    }

    final field = fieldClassification.field!;
    if (_sourceFor(source, parameterType) != field.typeSource) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    final parameterDecision = _planMappedFieldParameter(
      field: field,
      fieldName: fieldName,
      parameterOffset: parameter.offset,
      replacementOffset: field.leadingCommentSource != null
          ? parameter.offset
          : parameterType.offset,
      replacementEnd: parameter.name!.end,
    );
    if (parameterDecision is _PlannedConstructorParameter) {
      _usedPrivateInitializers.add(fieldName);
    }
    return parameterDecision;
  }

  _ConstructorParameterDecision _planMappedFieldParameter({
    required _FieldToParameterField field,
    required String fieldName,
    required int parameterOffset,
    required int replacementOffset,
    required int replacementEnd,
  }) {
    if (!_usedFieldNames.add(fieldName)) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    final shouldMoveComment = field.leadingCommentSource != null;
    final prefix = shouldMoveComment
        ? source.substring(parameterOffset, replacementOffset)
        : '';
    return _PlannedConstructorParameter(
      _ParameterMigrationPlan(
        edits: [
          SourceEdit(
            offset: replacementOffset - parametersOffset,
            length: replacementEnd - replacementOffset,
            replacement: _declaringParameterSource(
              field,
              fieldName,
              prefix: prefix,
            ),
          ),
        ],
        removableFields: [field.declaration],
      ),
    );
  }

  _FieldToParameterFieldClassification _classifyMappedField(String fieldName) {
    return _classifyFieldToParameterField(
      source: source,
      declaration: declaration,
      fieldName: fieldName,
    );
  }
}

DeclarationSkipReason? _mappedFieldSkipReason({
  required String source,
  required ClassDeclaration declaration,
  required String fieldName,
}) {
  return _classifyFieldToParameterField(
    source: source,
    declaration: declaration,
    fieldName: fieldName,
  ).skipReason;
}

_FieldToParameterFieldClassification _classifyFieldToParameterField({
  required String source,
  required ClassDeclaration declaration,
  required String fieldName,
}) {
  final field = _fieldDeclarationFor(declaration, fieldName);
  if (field == null) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.missingField,
    );
  }

  final (member, fieldList, variable) = field;
  if (member.isStatic) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.staticField,
    );
  }
  if (fieldList.isLate) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.lateField,
    );
  }
  if (member.externalKeyword != null) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.externalField,
    );
  }
  if (fieldList.variables.length != 1) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.multipleFieldVariables,
    );
  }
  if (member.metadata.isNotEmpty ||
      fieldList.metadata.isNotEmpty ||
      variable.metadata.isNotEmpty) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.fieldMetadata,
    );
  }

  final commentMigration = _fieldCommentMigration(
    source: source,
    declaration: declaration,
    member: member,
  );
  if (commentMigration.isAmbiguous) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.fieldComment,
    );
  }
  if (variable.initializer != null) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.initializedField,
    );
  }
  if (fieldList.type == null) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.implicitFieldType,
    );
  }
  if (member.abstractKeyword != null ||
      member.covariantKeyword != null ||
      fieldList.isConst) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.unsupportedFieldModifier,
    );
  }

  return _FieldToParameterFieldClassification.field(
    _FieldToParameterField(
      declaration: member,
      typeSource: _sourceFor(source, fieldList.type!),
      declaringKeyword: fieldList.isFinal ? 'final' : 'var',
      leadingCommentSource: commentMigration.source,
    ),
  );
}

class _FieldToParameterFieldClassification {
  const _FieldToParameterFieldClassification.field(this.field)
    : skipReason = null;

  const _FieldToParameterFieldClassification.skip(this.skipReason)
    : field = null;

  final _FieldToParameterField? field;
  final DeclarationSkipReason? skipReason;
}

class _FieldToParameterField {
  const _FieldToParameterField({
    required this.declaration,
    required this.typeSource,
    required this.declaringKeyword,
    this.leadingCommentSource,
  });

  final FieldDeclaration declaration;
  final String typeSource;
  final String declaringKeyword;
  final String? leadingCommentSource;
}

(FieldDeclaration, VariableDeclarationList, VariableDeclaration)?
_fieldDeclarationFor(ClassDeclaration declaration, String fieldName) {
  for (final member in declaration.body.members.whereType<FieldDeclaration>()) {
    for (final variable in member.fields.variables) {
      if (variable.name.lexeme == fieldName) {
        return (member, member.fields, variable);
      }
    }
  }
  return null;
}

String _declaringParameterSource(
  _FieldToParameterField field,
  String fieldName, {
  String prefix = '',
}) {
  final parameterSource =
      '$prefix${field.declaringKeyword} ${field.typeSource} $fieldName';
  final commentSource = field.leadingCommentSource;
  if (commentSource == null) {
    return parameterSource;
  }
  return '$commentSource\n$parameterSource';
}

bool _isSimpleFieldFormalParameter(FieldFormalParameter parameter) {
  return parameter.metadata.isEmpty &&
      parameter.documentationComment == null &&
      parameter.constFinalOrVarKeyword == null &&
      parameter.covariantKeyword == null &&
      parameter.type == null &&
      parameter.functionTypedSuffix == null;
}

bool _isSimpleRegularFormalParameter(RegularFormalParameter parameter) {
  return parameter.metadata.isEmpty &&
      parameter.documentationComment == null &&
      parameter.constFinalOrVarKeyword == null &&
      parameter.covariantKeyword == null &&
      parameter.functionTypedSuffix == null;
}
