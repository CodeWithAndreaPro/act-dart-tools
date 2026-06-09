part of '../migration.dart';

final class _FieldToParameterPlanner {
  _FieldToParameterPlanner({
    required this.source,
    required this.bodyInfo,
    required this.privateFieldInitializersByName,
  });

  final String source;
  final _DeclarationBodyInfo bodyInfo;
  final Map<String, String> privateFieldInitializersByName;
  final Set<String> _usedFieldNames = <String>{};
  final Set<String> _usedPrivateInitializers = <String>{};
  bool _usedRegularPassthroughParameter = false;

  bool get _hasUnusedPrivateFieldInitializers {
    return _usedPrivateInitializers.length !=
        privateFieldInitializersByName.length;
  }

  _FieldToParameterDecision decideConstructorParameters({
    required FormalParameterList parameters,
    required List<_FieldInitializerMigration> fieldInitializers,
  }) {
    final fieldFormalNames = _fieldFormalParameterNames(parameters);
    final parameterPlans = <_ParameterMigrationPlan>[];
    for (final parameter in parameters.parameters) {
      final parameterDecision =
          parameter is SuperFormalParameter &&
              _isSimpleSuperFormalParameter(parameter)
          ? const _PlannedConstructorParameter(_ParameterMigrationPlan())
          : _decideParameter(parameter, fieldFormalNames: fieldFormalNames);
      switch (parameterDecision) {
        case _PlannedConstructorParameter(:final plan):
          parameterPlans.add(plan);
        case _SkippedConstructorParameter(:final reason):
          return _SkippedFieldToParameter(reason);
      }
    }

    if (_hasUnusedPrivateFieldInitializers) {
      return const _SkippedFieldToParameter(
        DeclarationSkipReason.unsupportedInitializer,
      );
    }
    for (final fieldInitializer in fieldInitializers) {
      if (_usedFieldNames.contains(fieldInitializer.fieldName)) {
        return const _SkippedFieldToParameter(
          DeclarationSkipReason.unsupportedInitializer,
        );
      }
    }
    if (_usedRegularPassthroughParameter &&
        _usedFieldNames.isEmpty &&
        _usedPrivateInitializers.isEmpty &&
        fieldInitializers.isEmpty) {
      return const _SkippedFieldToParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }
    if (_hasUninitializedUnmappedFields(fieldInitializers)) {
      return const _SkippedFieldToParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    return _PlannedFieldToParameter(parameterPlans);
  }

  _ConstructorParameterDecision _decideParameter(
    FormalParameter parameter, {
    required Set<String> fieldFormalNames,
  }) {
    if (parameter.metadata.isNotEmpty && parameter is! FieldFormalParameter) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.parameterMetadata,
      );
    }

    if (parameter is FieldFormalParameter) {
      return _decideFieldFormalParameter(
        parameter,
        fieldFormalNames: fieldFormalNames,
      );
    }

    if (parameter is RegularFormalParameter) {
      return _decideRegularParameter(parameter);
    }

    return const _SkippedConstructorParameter(
      DeclarationSkipReason.unsupportedParameterShape,
    );
  }

  _ConstructorParameterDecision _decideFieldFormalParameter(
    FieldFormalParameter parameter, {
    required Set<String> fieldFormalNames,
  }) {
    if (!_isSimpleFieldFormalParameter(parameter)) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    final fieldName = parameter.name.lexeme;
    final fieldClassification = _classifyMappedField(
      fieldName,
      fieldFormalNames: fieldFormalNames,
    );
    if (fieldClassification.skipReason case final reason?) {
      return _SkippedConstructorParameter(reason);
    }

    final field = fieldClassification.field!;
    return _planMappedFieldParameter(
      field: field,
      fieldName: fieldName,
      parameterOffset: parameter.offset,
      prefixEndOffset: parameter.thisKeyword.offset,
      replacementOffset: field.leadingCommentSource != null
          ? parameter.offset
          : parameter.thisKeyword.offset,
      replacementEnd: parameter.name.end,
    );
  }

  _ConstructorParameterDecision _decideRegularParameter(
    RegularFormalParameter parameter,
  ) {
    if (!_isSimpleRegularFormalParameter(parameter)) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.unsupportedParameterShape,
      );
    }

    final privateFieldDecision = _decidePrivateNamedFieldParameter(parameter);
    if (privateFieldDecision != null) {
      return privateFieldDecision;
    }

    _usedRegularPassthroughParameter = true;
    return const _PlannedConstructorParameter(_ParameterMigrationPlan());
  }

  _ConstructorParameterDecision? _decidePrivateNamedFieldParameter(
    RegularFormalParameter parameter,
  ) {
    final parameterName = parameter.name?.lexeme;
    final parameterType = parameter.type;
    if (parameterName == null ||
        parameterName.startsWith('_') ||
        parameterType == null ||
        !parameter.isNamed) {
      return null;
    }

    final fieldName = '_$parameterName';
    if (privateFieldInitializersByName[fieldName] != parameterName) {
      return null;
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
      prefixEndOffset: parameterType.offset,
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

  bool _hasUninitializedUnmappedFields(
    List<_FieldInitializerMigration> fieldInitializers,
  ) {
    final fieldInitializerNames = {
      for (final fieldInitializer in fieldInitializers)
        fieldInitializer.fieldName,
    };
    for (final member in bodyInfo.members.whereType<FieldDeclaration>()) {
      if (member.isStatic ||
          member.fields.isLate ||
          member.externalKeyword != null) {
        continue;
      }
      for (final variable in member.fields.variables) {
        if (variable.initializer != null ||
            _usedFieldNames.contains(variable.name.lexeme) ||
            fieldInitializerNames.contains(variable.name.lexeme)) {
          continue;
        }
        if (!_isNullableUninitializedRetainedField(member.fields)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isNullableUninitializedRetainedField(VariableDeclarationList fields) {
    final type = fields.type;
    return !fields.isFinal &&
        !fields.isConst &&
        type != null &&
        _sourceFor(source, type).trimRight().endsWith('?');
  }

  _ConstructorParameterDecision _planMappedFieldParameter({
    required _FieldToParameterField field,
    required String fieldName,
    required int parameterOffset,
    required int prefixEndOffset,
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
        ? source.substring(parameterOffset, prefixEndOffset)
        : '';
    return _PlannedConstructorParameter(
      _ParameterMigrationPlan(
        edits: [
          SourceEdit.replace(
            SourceRange.fromStartEnd(
              start: replacementOffset,
              end: replacementEnd,
            ),
            _declaringParameterSource(field, fieldName, prefix: prefix),
          ),
        ],
        removableFields: [field.declaration],
      ),
    );
  }

  _FieldToParameterFieldClassification _classifyMappedField(
    String fieldName, {
    Set<String> fieldFormalNames = const <String>{},
  }) {
    return _classifyFieldToParameterField(
      source: source,
      bodyInfo: bodyInfo,
      fieldName: fieldName,
      fieldFormalNames: fieldFormalNames,
    );
  }
}

sealed class _FieldToParameterDecision {
  const _FieldToParameterDecision();
}

final class _PlannedFieldToParameter extends _FieldToParameterDecision {
  const _PlannedFieldToParameter(this.parameterPlans);

  final List<_ParameterMigrationPlan> parameterPlans;
}

final class _SkippedFieldToParameter extends _FieldToParameterDecision {
  const _SkippedFieldToParameter(this.reason);

  final DeclarationSkipReason reason;
}

sealed class _ConstructorParameterDecision {
  const _ConstructorParameterDecision();
}

final class _PlannedConstructorParameter extends _ConstructorParameterDecision {
  const _PlannedConstructorParameter(this.plan);

  final _ParameterMigrationPlan plan;
}

final class _SkippedConstructorParameter extends _ConstructorParameterDecision {
  const _SkippedConstructorParameter(this.reason);

  final DeclarationSkipReason reason;
}

DeclarationSkipReason? _mappedFieldSkipReason({
  required String source,
  required _DeclarationBodyInfo bodyInfo,
  required String fieldName,
}) {
  return _classifyFieldToParameterField(
    source: source,
    bodyInfo: bodyInfo,
    fieldName: fieldName,
  ).skipReason;
}

_FieldToParameterFieldClassification _classifyFieldToParameterField({
  required String source,
  required _DeclarationBodyInfo bodyInfo,
  required String fieldName,
  Set<String> fieldFormalNames = const <String>{},
}) {
  final field = _fieldDeclarationFor(bodyInfo, fieldName);
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
  if (member.metadata.isNotEmpty ||
      fieldList.metadata.isNotEmpty ||
      fieldList.variables.any((variable) => variable.metadata.isNotEmpty)) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.fieldMetadata,
    );
  }

  final commentMigration = _fieldCommentMigration(
    source: source,
    bodyInfo: bodyInfo,
    member: member,
  );
  if (commentMigration.isAmbiguous) {
    return const _FieldToParameterFieldClassification.skip(
      DeclarationSkipReason.fieldComment,
    );
  }
  if (fieldList.variables.length != 1) {
    if (!_allFieldVariablesMappedByFieldFormals(fieldList, fieldFormalNames)) {
      return const _FieldToParameterFieldClassification.skip(
        DeclarationSkipReason.multipleFieldVariables,
      );
    }
    if (commentMigration.source != null) {
      return const _FieldToParameterFieldClassification.skip(
        DeclarationSkipReason.fieldComment,
      );
    }
  }
  if (fieldList.variables.any((variable) => variable.initializer != null)) {
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
_fieldDeclarationFor(_DeclarationBodyInfo bodyInfo, String fieldName) {
  for (final member in bodyInfo.members.whereType<FieldDeclaration>()) {
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
  return parameter.documentationComment == null &&
      parameter.constFinalOrVarKeyword == null &&
      parameter.covariantKeyword == null &&
      parameter.type == null &&
      parameter.functionTypedSuffix == null;
}

Set<String> _fieldFormalParameterNames(FormalParameterList parameters) {
  return {
    for (final parameter in parameters.parameters)
      if (parameter is FieldFormalParameter) parameter.name.lexeme,
  };
}

bool _allFieldVariablesMappedByFieldFormals(
  VariableDeclarationList fields,
  Set<String> fieldFormalNames,
) {
  for (final variable in fields.variables) {
    if (!fieldFormalNames.contains(variable.name.lexeme)) {
      return false;
    }
  }
  return true;
}

bool _isSimpleRegularFormalParameter(RegularFormalParameter parameter) {
  return parameter.metadata.isEmpty &&
      parameter.documentationComment == null &&
      parameter.constFinalOrVarKeyword == null &&
      parameter.covariantKeyword == null &&
      parameter.functionTypedSuffix == null;
}

bool _isSimpleSuperFormalParameter(SuperFormalParameter parameter) {
  return parameter.metadata.isEmpty &&
      parameter.documentationComment == null &&
      parameter.constFinalOrVarKeyword == null &&
      parameter.covariantKeyword == null &&
      parameter.type == null &&
      parameter.functionTypedSuffix == null;
}
