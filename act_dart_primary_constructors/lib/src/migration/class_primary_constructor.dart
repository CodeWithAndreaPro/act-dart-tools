part of '../migration.dart';

DeclarationSkipReason? _primaryConstructorSkipReason({
  required String source,
  required ClassDeclaration declaration,
}) {
  if (declaration.namePart is PrimaryConstructorDeclaration) {
    return null;
  }

  final constructors = declaration.body.members
      .whereType<ConstructorDeclaration>()
      .toList();
  if (constructors.isEmpty) {
    return null;
  }

  final generativeConstructors = constructors
      .where((constructor) => constructor.factoryKeyword == null)
      .toList();
  if (generativeConstructors.isEmpty) {
    return null;
  }

  final unnamedConstructors = generativeConstructors
      .where(_isUnnamedConstructor)
      .toList();
  if (unnamedConstructors.isEmpty) {
    return null;
  }
  if (unnamedConstructors.length > 1) {
    return DeclarationSkipReason.multipleConstructors;
  }

  final constructor = unnamedConstructors.single;
  if (constructor.externalKeyword != null) {
    return DeclarationSkipReason.externalConstructor;
  }
  if (constructor.metadata.isNotEmpty) {
    return DeclarationSkipReason.constructorMetadata;
  }
  if (constructor.documentationComment != null) {
    return DeclarationSkipReason.constructorComment;
  }
  if (constructor.redirectedConstructor != null) {
    return DeclarationSkipReason.redirectingConstructor;
  }
  final bodySkipReason = _constructorBodySkipReason(
    declaration: declaration,
    constructor: constructor,
  );
  if (bodySkipReason != null) {
    return bodySkipReason;
  }
  final initializerClassification = _classifyConstructorInitializers(
    source: source,
    declaration: declaration,
    constructor: constructor,
    parameterNames: _constructorParameterNames(constructor),
  );
  if (initializerClassification.skipReason case final skipReason?) {
    return skipReason;
  }
  final initializerPlan = initializerClassification.plan!;
  final privateFieldInitializersByName =
      initializerPlan.privateFieldInitializersByName;

  if (generativeConstructors.any(
    (constructor) =>
        constructor.externalKeyword == null &&
        constructor != unnamedConstructors.single &&
        !_isUnnamedConstructor(constructor),
  )) {
    return DeclarationSkipReason.namedConstructor;
  }
  if (constructor.parameters.parameters.isEmpty &&
      constructor.constKeyword == null &&
      declaration.body.members.length != 1) {
    return DeclarationSkipReason.emptyNonConstConstructorWithMembers;
  }

  final usedFieldNames = <String>{};
  final usedPrivateInitializers = <String>{};
  for (final parameter in constructor.parameters.parameters) {
    final parameterSkipReason = _parameterSkipReason(
      source: source,
      declaration: declaration,
      parameter: parameter,
      privateFieldInitializersByName: privateFieldInitializersByName,
      usedFieldNames: usedFieldNames,
      usedPrivateInitializers: usedPrivateInitializers,
    );
    if (parameterSkipReason != null) {
      return parameterSkipReason;
    }
  }

  if (usedPrivateInitializers.length != privateFieldInitializersByName.length) {
    return DeclarationSkipReason.unsupportedInitializer;
  }
  for (final fieldInitializer in initializerPlan.fieldInitializers) {
    if (usedFieldNames.contains(fieldInitializer.fieldName)) {
      return DeclarationSkipReason.unsupportedInitializer;
    }
  }

  return null;
}

DeclarationSkipReason? _parameterSkipReason({
  required String source,
  required ClassDeclaration declaration,
  required FormalParameter parameter,
  required Map<String, String> privateFieldInitializersByName,
  required Set<String> usedFieldNames,
  required Set<String> usedPrivateInitializers,
}) {
  if (parameter.metadata.isNotEmpty) {
    return DeclarationSkipReason.parameterMetadata;
  }

  if (parameter is FieldFormalParameter) {
    if (parameter.documentationComment != null ||
        parameter.constFinalOrVarKeyword != null ||
        parameter.covariantKeyword != null ||
        parameter.type != null ||
        parameter.functionTypedSuffix != null) {
      return DeclarationSkipReason.unsupportedParameterShape;
    }
    final fieldName = parameter.name.lexeme;
    final fieldSkipReason = _mappedFieldSkipReason(
      source: source,
      declaration: declaration,
      fieldName: fieldName,
    );
    if (fieldSkipReason != null) {
      return fieldSkipReason;
    }
    if (!usedFieldNames.add(fieldName)) {
      return DeclarationSkipReason.unsupportedParameterShape;
    }
    return null;
  }

  if (parameter is RegularFormalParameter) {
    if (parameter.documentationComment != null ||
        parameter.constFinalOrVarKeyword != null ||
        parameter.covariantKeyword != null ||
        parameter.functionTypedSuffix != null) {
      return DeclarationSkipReason.unsupportedParameterShape;
    }
    final parameterName = parameter.name?.lexeme;
    final parameterType = parameter.type;
    if (parameterName == null ||
        parameterName.startsWith('_') ||
        parameterType == null ||
        !parameter.isNamed) {
      return DeclarationSkipReason.unsupportedParameterShape;
    }

    final fieldName = '_$parameterName';
    if (privateFieldInitializersByName[fieldName] != parameterName) {
      return DeclarationSkipReason.unsupportedParameterShape;
    }
    final fieldSkipReason = _mappedFieldSkipReason(
      source: source,
      declaration: declaration,
      fieldName: fieldName,
    );
    if (fieldSkipReason != null) {
      return fieldSkipReason;
    }
    final field = _eligibleFieldsByName(declaration, source)[fieldName];
    if (field == null ||
        _sourceFor(source, parameterType) != field.typeSource) {
      return DeclarationSkipReason.unsupportedParameterShape;
    }
    if (!usedFieldNames.add(fieldName)) {
      return DeclarationSkipReason.unsupportedParameterShape;
    }
    usedPrivateInitializers.add(fieldName);
    return null;
  }

  if (parameter is SuperFormalParameter &&
      _isSimpleSuperFormalParameter(parameter)) {
    return null;
  }

  return DeclarationSkipReason.unsupportedParameterShape;
}

DeclarationSkipReason? _mappedFieldSkipReason({
  required String source,
  required ClassDeclaration declaration,
  required String fieldName,
}) {
  final field = _fieldDeclarationFor(declaration, fieldName);
  if (field == null) {
    return DeclarationSkipReason.missingField;
  }

  final (member, fieldList, variable) = field;
  if (member.isStatic) {
    return DeclarationSkipReason.staticField;
  }
  if (fieldList.isLate) {
    return DeclarationSkipReason.lateField;
  }
  if (member.externalKeyword != null) {
    return DeclarationSkipReason.externalField;
  }
  if (fieldList.variables.length != 1) {
    return DeclarationSkipReason.multipleFieldVariables;
  }
  if (member.metadata.isNotEmpty ||
      fieldList.metadata.isNotEmpty ||
      variable.metadata.isNotEmpty) {
    return DeclarationSkipReason.fieldMetadata;
  }
  if (_fieldCommentMigration(
    source: source,
    declaration: declaration,
    member: member,
  ).isAmbiguous) {
    return DeclarationSkipReason.fieldComment;
  }
  if (variable.initializer != null) {
    return DeclarationSkipReason.initializedField;
  }
  if (fieldList.type == null) {
    return DeclarationSkipReason.implicitFieldType;
  }
  if (member.abstractKeyword != null ||
      member.covariantKeyword != null ||
      fieldList.isConst) {
    return DeclarationSkipReason.unsupportedFieldModifier;
  }
  return null;
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

bool _isUnnamedConstructor(ConstructorDeclaration constructor) {
  return constructor.name == null && constructor.period == null;
}

_ClassMigrationPlan? _planClassMigration({
  required String source,
  required TargetDartFile targetFile,
  required ClassDeclaration declaration,
}) {
  if (declaration.namePart is PrimaryConstructorDeclaration) {
    return null;
  }

  final constructor = _eligibleUnnamedConstructor(declaration);
  if (constructor == null) {
    return null;
  }

  final constructorParameters = constructor.parameters.parameters;
  if (constructorParameters.isEmpty &&
      constructor.constKeyword == null &&
      declaration.body.members.length != 1) {
    return null;
  }

  final fieldsByName = _eligibleFieldsByName(declaration, source);
  final initializerClassification = _classifyConstructorInitializers(
    source: source,
    declaration: declaration,
    constructor: constructor,
    parameterNames: _constructorParameterNames(constructor),
  );
  final initializerPlan = initializerClassification.plan;
  if (initializerPlan == null) {
    return null;
  }
  final privateFieldInitializersByName =
      initializerPlan.privateFieldInitializersByName;
  final parameterEdits = <SourceEdit>[];
  final retainedInitializers = initializerPlan.retainedInitializers;
  final primaryBodyRequired =
      retainedInitializers.isNotEmpty || constructor.body is BlockFunctionBody;
  final removableMembers = <ClassMember>{if (!primaryBodyRequired) constructor};
  final fieldNames = <String>{};
  final usedPrivateInitializers = <String>{};
  final parametersOffset = constructor.parameters.offset;
  final parametersSource = _sourceFor(source, constructor.parameters);

  for (final parameter in constructorParameters) {
    final parameterPlan = _planConstructorParameter(
      source: source,
      parameter: parameter,
      fieldsByName: fieldsByName,
      privateFieldInitializersByName: privateFieldInitializersByName,
      parametersOffset: parametersOffset,
    );
    if (parameterPlan == null) {
      return null;
    }
    for (final fieldName in parameterPlan.fieldNames) {
      if (!fieldNames.add(fieldName)) {
        return null;
      }
    }
    parameterEdits.addAll(parameterPlan.edits);
    removableMembers.addAll(parameterPlan.removableFields);
    usedPrivateInitializers.addAll(parameterPlan.privateInitializerFieldNames);
  }

  if (usedPrivateInitializers.length != privateFieldInitializersByName.length) {
    return null;
  }
  for (final fieldInitializer in initializerPlan.fieldInitializers) {
    if (fieldNames.contains(fieldInitializer.fieldName)) {
      return null;
    }
  }

  final primaryParameters =
      constructorParameters.isEmpty && constructor.constKeyword == null
      ? null
      : applySourceEdits(parametersSource, parameterEdits);
  final edits = <SourceEdit>[
    if (constructor.constKeyword != null)
      SourceEdit(
        offset: declaration.classKeyword.end,
        length: 0,
        replacement: ' const',
      ),
    if (primaryParameters != null)
      SourceEdit(
        offset: declaration.namePart.end,
        length: 0,
        replacement: primaryParameters,
      ),
    for (final fieldInitializer in initializerPlan.fieldInitializers)
      SourceEdit(
        offset: fieldInitializer.variable.end,
        length: 0,
        replacement: ' = ${_sourceFor(source, fieldInitializer.expression)}',
      ),
  ];

  if (!primaryBodyRequired &&
      declaration.body.members.length == removableMembers.length) {
    edits.add(
      SourceEdit(
        offset: declaration.body.offset,
        length: declaration.body.length,
        replacement: ';',
      ),
    );
  } else {
    for (final member in removableMembers) {
      final range = _memberRemovalRange(source, member);
      edits.add(
        SourceEdit(offset: range.offset, length: range.length, replacement: ''),
      );
    }
    if (primaryBodyRequired) {
      final range = _memberRemovalRange(source, constructor);
      edits.add(
        SourceEdit(
          offset: range.offset,
          length: range.length,
          replacement: _primaryConstructorBodySource(
            source: source,
            constructor: constructor,
            retainedInitializers: retainedInitializers,
          ),
        ),
      );
    }
  }

  return _ClassMigrationPlan(
    edits: edits,
    reportEntry: {
      'path': targetFile.relativePath,
      'declarationKind': 'class',
      'declarationName': declaration.namePart.typeName.lexeme,
      'transform': primaryConstructorTransform,
      'offset': declaration.offset,
    },
  );
}

ConstructorDeclaration? _eligibleUnnamedConstructor(
  ClassDeclaration declaration,
) {
  final constructors = declaration.body.members
      .whereType<ConstructorDeclaration>();
  ConstructorDeclaration? unnamed;
  for (final constructor in constructors) {
    if (constructor.factoryKeyword != null ||
        constructor.externalKeyword != null) {
      continue;
    }
    if (constructor.name != null || constructor.period != null) {
      return null;
    }
    if (unnamed != null ||
        constructor.redirectedConstructor != null ||
        !_isSupportedConstructorBodyShape(constructor.body)) {
      return null;
    }
    unnamed = constructor;
  }
  return unnamed;
}

Map<String, _EligibleField> _eligibleFieldsByName(
  ClassDeclaration declaration,
  String source,
) {
  final fields = <String, _EligibleField>{};
  for (final member in declaration.body.members.whereType<FieldDeclaration>()) {
    final fieldList = member.fields;
    if (member.isStatic ||
        member.externalKeyword != null ||
        member.abstractKeyword != null ||
        member.covariantKeyword != null ||
        fieldList.isLate ||
        fieldList.isConst ||
        fieldList.type == null ||
        fieldList.metadata.isNotEmpty ||
        member.metadata.isNotEmpty ||
        fieldList.variables.length != 1) {
      continue;
    }
    final commentMigration = _fieldCommentMigration(
      source: source,
      declaration: declaration,
      member: member,
    );
    if (commentMigration.isAmbiguous) {
      continue;
    }
    final variable = fieldList.variables.single;
    if (variable.initializer != null) {
      continue;
    }
    fields[variable.name.lexeme] = _EligibleField(
      declaration: member,
      variable: variable,
      typeSource: _sourceFor(source, fieldList.type!),
      declaringKeyword: fieldList.isFinal ? 'final' : 'var',
      leadingCommentSource: commentMigration.source,
    );
  }
  return fields;
}

_ParameterMigrationPlan? _planConstructorParameter({
  required String source,
  required FormalParameter parameter,
  required Map<String, _EligibleField> fieldsByName,
  required Map<String, String> privateFieldInitializersByName,
  required int parametersOffset,
}) {
  if (parameter is FieldFormalParameter) {
    return _planFieldFormalParameter(
      source: source,
      parameter: parameter,
      fieldsByName: fieldsByName,
      parametersOffset: parametersOffset,
    );
  }
  if (parameter is RegularFormalParameter) {
    return _planPrivateFieldParameter(
      source: source,
      parameter: parameter,
      fieldsByName: fieldsByName,
      privateFieldInitializersByName: privateFieldInitializersByName,
      parametersOffset: parametersOffset,
    );
  }
  if (parameter is SuperFormalParameter &&
      _isSimpleSuperFormalParameter(parameter)) {
    return const _ParameterMigrationPlan();
  }
  return null;
}

_ParameterMigrationPlan? _planFieldFormalParameter({
  required String source,
  required FieldFormalParameter parameter,
  required Map<String, _EligibleField> fieldsByName,
  required int parametersOffset,
}) {
  final fieldName = parameter.name.lexeme;
  final field = fieldsByName[fieldName];
  if (field == null || !_isSimpleFieldFormalParameter(parameter)) {
    return null;
  }
  final shouldMoveComment = field.leadingCommentSource != null;
  final replacementOffset = shouldMoveComment
      ? parameter.offset
      : parameter.thisKeyword.offset;
  final prefix = shouldMoveComment
      ? source.substring(parameter.offset, parameter.thisKeyword.offset)
      : '';
  return _ParameterMigrationPlan(
    edits: [
      SourceEdit(
        offset: replacementOffset - parametersOffset,
        length: parameter.name.end - replacementOffset,
        replacement: _declaringParameterSource(
          field,
          fieldName,
          prefix: prefix,
        ),
      ),
    ],
    removableFields: [field.declaration],
    fieldNames: [fieldName],
  );
}

_ParameterMigrationPlan? _planPrivateFieldParameter({
  required String source,
  required RegularFormalParameter parameter,
  required Map<String, _EligibleField> fieldsByName,
  required Map<String, String> privateFieldInitializersByName,
  required int parametersOffset,
}) {
  final parameterName = parameter.name?.lexeme;
  final parameterType = parameter.type;
  if (parameterName == null ||
      parameterName.startsWith('_') ||
      parameterType == null ||
      !parameter.isNamed ||
      !_isSimpleRegularFormalParameter(parameter)) {
    return null;
  }

  final fieldName = '_$parameterName';
  final field = fieldsByName[fieldName];
  if (field == null ||
      privateFieldInitializersByName[fieldName] != parameterName ||
      _sourceFor(source, parameterType) != field.typeSource) {
    return null;
  }

  final shouldMoveComment = field.leadingCommentSource != null;
  final replacementOffset = shouldMoveComment
      ? parameter.offset
      : parameterType.offset;
  final prefix = shouldMoveComment
      ? source.substring(parameter.offset, parameterType.offset)
      : '';

  return _ParameterMigrationPlan(
    edits: [
      SourceEdit(
        offset: replacementOffset - parametersOffset,
        length: parameter.name!.end - replacementOffset,
        replacement: _declaringParameterSource(
          field,
          fieldName,
          prefix: prefix,
        ),
      ),
    ],
    removableFields: [field.declaration],
    fieldNames: [fieldName],
    privateInitializerFieldNames: [fieldName],
  );
}

String _primaryConstructorBodySource({
  required String source,
  required ConstructorDeclaration constructor,
  required List<ConstructorInitializer> retainedInitializers,
}) {
  final indent = _lineIndentation(source, constructor.offset);
  final initializerSource = retainedInitializers.isEmpty
      ? ''
      : ' : ${retainedInitializers.map((initializer) => _sourceFor(source, initializer)).join(', ')}';
  final body = constructor.body;
  final bodySource = body is BlockFunctionBody
      ? ' ${_sourceFor(source, body)}'
      : ';';
  return '${indent}this$initializerSource$bodySource\n';
}

String _declaringParameterSource(
  _EligibleField field,
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

bool _isSimpleSuperFormalParameter(SuperFormalParameter parameter) {
  return parameter.metadata.isEmpty &&
      parameter.documentationComment == null &&
      parameter.constFinalOrVarKeyword == null &&
      parameter.covariantKeyword == null &&
      parameter.type == null &&
      parameter.functionTypedSuffix == null;
}
