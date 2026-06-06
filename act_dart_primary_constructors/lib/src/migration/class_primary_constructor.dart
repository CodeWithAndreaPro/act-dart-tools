part of '../migration.dart';

class _ClassPrimaryConstructorPlanner {
  const _ClassPrimaryConstructorPlanner({
    required this.source,
    required this.targetFile,
    required this.declaration,
  });

  final String source;
  final TargetDartFile targetFile;
  final ClassDeclaration declaration;

  _ClassPrimaryConstructorDecision decide() {
    if (declaration.namePart is PrimaryConstructorDeclaration) {
      return const _NoOpClassPrimaryConstructor();
    }

    final constructors = declaration.body.members
        .whereType<ConstructorDeclaration>()
        .toList();
    if (constructors.isEmpty) {
      return const _NoOpClassPrimaryConstructor();
    }

    final generativeConstructors = constructors
        .where((constructor) => constructor.factoryKeyword == null)
        .toList();
    if (generativeConstructors.isEmpty) {
      return const _NoOpClassPrimaryConstructor();
    }

    final unnamedConstructors = generativeConstructors
        .where(_isUnnamedConstructor)
        .toList();
    if (unnamedConstructors.isEmpty) {
      return const _NoOpClassPrimaryConstructor();
    }
    if (unnamedConstructors.length > 1) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.multipleConstructors,
      );
    }

    final constructor = unnamedConstructors.single;
    if (constructor.externalKeyword != null) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.externalConstructor,
      );
    }
    if (constructor.metadata.isNotEmpty) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.constructorMetadata,
      );
    }
    if (constructor.documentationComment != null) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.constructorComment,
      );
    }
    if (constructor.redirectedConstructor != null) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.redirectingConstructor,
      );
    }
    final bodySkipReason = _constructorBodySkipReason(
      declaration: declaration,
      constructor: constructor,
    );
    if (bodySkipReason != null) {
      return _SkippedClassPrimaryConstructor(bodySkipReason);
    }
    final initializerClassification = _classifyConstructorInitializers(
      source: source,
      declaration: declaration,
      constructor: constructor,
      parameterNames: _constructorParameterNames(constructor),
    );
    if (initializerClassification.skipReason case final skipReason?) {
      return _SkippedClassPrimaryConstructor(skipReason);
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
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.namedConstructor,
      );
    }
    if (constructor.parameters.parameters.isEmpty &&
        constructor.constKeyword == null &&
        declaration.body.members.length != 1) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.emptyNonConstConstructorWithMembers,
      );
    }

    final usedFieldNames = <String>{};
    final usedPrivateInitializers = <String>{};
    final fieldsByName = _eligibleFieldsByName();
    final parameterPlans = <_ParameterMigrationPlan>[];
    final parametersOffset = constructor.parameters.offset;
    for (final parameter in constructor.parameters.parameters) {
      final parameterDecision = _decideConstructorParameter(
        parameter: parameter,
        fieldsByName: fieldsByName,
        privateFieldInitializersByName: privateFieldInitializersByName,
        usedFieldNames: usedFieldNames,
        usedPrivateInitializers: usedPrivateInitializers,
        parametersOffset: parametersOffset,
      );
      switch (parameterDecision) {
        case _PlannedConstructorParameter(:final plan):
          parameterPlans.add(plan);
        case _SkippedConstructorParameter(:final reason):
          return _SkippedClassPrimaryConstructor(reason);
      }
    }

    if (usedPrivateInitializers.length !=
        privateFieldInitializersByName.length) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.unsupportedInitializer,
      );
    }
    for (final fieldInitializer in initializerPlan.fieldInitializers) {
      if (usedFieldNames.contains(fieldInitializer.fieldName)) {
        return const _SkippedClassPrimaryConstructor(
          DeclarationSkipReason.unsupportedInitializer,
        );
      }
    }

    return _MigratedClassPrimaryConstructor(
      _buildMigrationPlan(
        constructor: constructor,
        initializerPlan: initializerPlan,
        parameterPlans: parameterPlans,
      ),
    );
  }

  _ClassMigrationPlan _buildMigrationPlan({
    required ConstructorDeclaration constructor,
    required _ConstructorInitializerPlan initializerPlan,
    required List<_ParameterMigrationPlan> parameterPlans,
  }) {
    final constructorParameters = constructor.parameters.parameters;
    final parameterEdits = <SourceEdit>[];
    final retainedInitializers = initializerPlan.retainedInitializers;
    final primaryBodyRequired =
        retainedInitializers.isNotEmpty ||
        constructor.body is BlockFunctionBody;
    final removableMembers = <ClassMember>{
      if (!primaryBodyRequired) constructor,
    };
    final parametersSource = _sourceFor(source, constructor.parameters);

    for (final parameterPlan in parameterPlans) {
      parameterEdits.addAll(parameterPlan.edits);
      removableMembers.addAll(parameterPlan.removableFields);
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
          SourceEdit(
            offset: range.offset,
            length: range.length,
            replacement: '',
          ),
        );
      }
      if (primaryBodyRequired) {
        final range = _memberRemovalRange(source, constructor);
        edits.add(
          SourceEdit(
            offset: range.offset,
            length: range.length,
            replacement: _primaryConstructorBodySource(
              constructor: constructor,
              retainedInitializers: retainedInitializers,
            ),
          ),
        );
      }
    }

    return _ClassMigrationPlan(
      edits: edits,
      migratedDeclaration: _MigratedDeclaration(
        path: targetFile.relativePath,
        declarationKind: 'class',
        declarationName: declaration.namePart.typeName.lexeme,
        transform: primaryConstructorTransform,
        offset: declaration.offset,
      ),
    );
  }

  _ConstructorParameterDecision _decideConstructorParameter({
    required FormalParameter parameter,
    required Map<String, _EligibleField> fieldsByName,
    required Map<String, String> privateFieldInitializersByName,
    required Set<String> usedFieldNames,
    required Set<String> usedPrivateInitializers,
    required int parametersOffset,
  }) {
    if (parameter.metadata.isNotEmpty) {
      return const _SkippedConstructorParameter(
        DeclarationSkipReason.parameterMetadata,
      );
    }

    if (parameter is FieldFormalParameter) {
      if (!_isSimpleFieldFormalParameter(parameter)) {
        return const _SkippedConstructorParameter(
          DeclarationSkipReason.unsupportedParameterShape,
        );
      }
      final fieldName = parameter.name.lexeme;
      final fieldSkipReason = _mappedFieldSkipReason(
        source: source,
        declaration: declaration,
        fieldName: fieldName,
      );
      if (fieldSkipReason != null) {
        return _SkippedConstructorParameter(fieldSkipReason);
      }
      if (!usedFieldNames.add(fieldName)) {
        return const _SkippedConstructorParameter(
          DeclarationSkipReason.unsupportedParameterShape,
        );
      }
      final field = fieldsByName[fieldName];
      if (field == null) {
        return const _SkippedConstructorParameter(
          DeclarationSkipReason.unsupportedParameterShape,
        );
      }
      final shouldMoveComment = field.leadingCommentSource != null;
      final replacementOffset = shouldMoveComment
          ? parameter.offset
          : parameter.thisKeyword.offset;
      final prefix = shouldMoveComment
          ? source.substring(parameter.offset, parameter.thisKeyword.offset)
          : '';
      return _PlannedConstructorParameter(
        _ParameterMigrationPlan(
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
        ),
      );
    }

    if (parameter is RegularFormalParameter) {
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
      final fieldSkipReason = _mappedFieldSkipReason(
        source: source,
        declaration: declaration,
        fieldName: fieldName,
      );
      if (fieldSkipReason != null) {
        return _SkippedConstructorParameter(fieldSkipReason);
      }
      final field = fieldsByName[fieldName];
      if (field == null ||
          _sourceFor(source, parameterType) != field.typeSource) {
        return const _SkippedConstructorParameter(
          DeclarationSkipReason.unsupportedParameterShape,
        );
      }
      if (!usedFieldNames.add(fieldName)) {
        return const _SkippedConstructorParameter(
          DeclarationSkipReason.unsupportedParameterShape,
        );
      }
      usedPrivateInitializers.add(fieldName);
      final shouldMoveComment = field.leadingCommentSource != null;
      final replacementOffset = shouldMoveComment
          ? parameter.offset
          : parameterType.offset;
      final prefix = shouldMoveComment
          ? source.substring(parameter.offset, parameterType.offset)
          : '';
      return _PlannedConstructorParameter(
        _ParameterMigrationPlan(
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
        ),
      );
    }

    if (parameter is SuperFormalParameter &&
        _isSimpleSuperFormalParameter(parameter)) {
      return const _PlannedConstructorParameter(_ParameterMigrationPlan());
    }

    return const _SkippedConstructorParameter(
      DeclarationSkipReason.unsupportedParameterShape,
    );
  }

  Map<String, _EligibleField> _eligibleFieldsByName() {
    final fields = <String, _EligibleField>{};
    for (final member
        in declaration.body.members.whereType<FieldDeclaration>()) {
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

  String _primaryConstructorBodySource({
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
}

sealed class _ClassPrimaryConstructorDecision {
  const _ClassPrimaryConstructorDecision();
}

final class _MigratedClassPrimaryConstructor
    extends _ClassPrimaryConstructorDecision {
  const _MigratedClassPrimaryConstructor(this.plan);

  final _ClassMigrationPlan plan;
}

final class _SkippedClassPrimaryConstructor
    extends _ClassPrimaryConstructorDecision {
  const _SkippedClassPrimaryConstructor(this.reason);

  final DeclarationSkipReason reason;
}

final class _NoOpClassPrimaryConstructor
    extends _ClassPrimaryConstructorDecision {
  const _NoOpClassPrimaryConstructor();
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
