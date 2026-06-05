import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'discovery.dart';
import 'source_edit.dart';

const primaryConstructorTransform = 'primaryConstructor';

enum DeclarationSkipReason {
  multipleConstructors(
    'multipleConstructors',
    'Multiple generative constructors are not supported.',
  ),
  namedConstructor(
    'namedConstructor',
    'Named generative constructors are not supported.',
  ),
  externalConstructor(
    'externalConstructor',
    'External constructors are not supported.',
  ),
  redirectingConstructor(
    'redirectingConstructor',
    'Redirecting constructors are not supported.',
  ),
  nonEmptyConstructorBody(
    'nonEmptyConstructorBody',
    'Non-empty constructor bodies are not supported.',
  ),
  fieldInitializingConstructorBody(
    'fieldInitializingConstructorBody',
    'Constructor bodies that initialize instance fields are not supported.',
  ),
  unsupportedConstructorBody(
    'unsupportedConstructorBody',
    'This constructor body shape is not supported.',
  ),
  emptyNonConstConstructorWithMembers(
    'emptyNonConstConstructorWithMembers',
    'Empty non-const constructors without parameters are only supported when '
        'the class body can collapse.',
  ),
  constructorMetadata(
    'constructorMetadata',
    'Constructor metadata is not moved to primary constructors.',
  ),
  constructorComment(
    'constructorComment',
    'Constructor comments are not moved to primary constructors.',
  ),
  parameterMetadata(
    'parameterMetadata',
    'Parameter metadata is not moved to declaring parameters.',
  ),
  fieldMetadata(
    'fieldMetadata',
    'Field metadata is not moved to declaring parameters.',
  ),
  fieldComment(
    'fieldComment',
    'Ambiguous field comments are not moved to declaring parameters.',
  ),
  missingField(
    'missingField',
    'A constructor parameter maps to a missing field.',
  ),
  staticField(
    'staticField',
    'Static fields cannot become declaring parameters.',
  ),
  lateField('lateField', 'Late fields cannot become declaring parameters.'),
  externalField(
    'externalField',
    'External fields cannot become declaring parameters.',
  ),
  initializedField(
    'initializedField',
    'Initialized fields cannot become declaring parameters.',
  ),
  implicitFieldType(
    'implicitFieldType',
    'Fields with implicit types cannot become declaring parameters.',
  ),
  multipleFieldVariables(
    'multipleFieldVariables',
    'Multi-variable field declarations cannot become declaring parameters.',
  ),
  unsupportedFieldModifier(
    'unsupportedFieldModifier',
    'This field modifier is not supported for declaring parameters.',
  ),
  unsupportedParameterShape(
    'unsupportedParameterShape',
    'This constructor parameter shape is not supported.',
  ),
  unsafeInitializerDependency(
    'unsafeInitializerDependency',
    'Initializer field assignments must depend only on constructor parameters.',
  ),
  unsupportedInitializer(
    'unsupportedInitializer',
    'This constructor initializer is not supported.',
  ),
  namedSuperInitializer(
    'namedSuperInitializer',
    'Named super constructor initializers are not supported.',
  );

  const DeclarationSkipReason(this.code, this.message);

  final String code;
  final String message;
}

class MigrationRunResult {
  const MigrationRunResult({
    required this.changedFiles,
    required this.migratedDeclarations,
    required this.skippedDeclarations,
    required this.transformCounts,
    required this.skipReasonCounts,
  });

  final List<String> changedFiles;
  final List<Map<String, Object?>> migratedDeclarations;
  final List<Map<String, Object?>> skippedDeclarations;
  final Map<String, int> transformCounts;
  final Map<String, int> skipReasonCounts;
}

class MigrationFailure implements Exception {
  const MigrationFailure(this.message, {required this.isInputParseFailure});

  final String message;
  final bool isInputParseFailure;

  @override
  String toString() => 'MigrationFailure: $message';
}

MigrationRunResult migrateTargetPackageFiles({
  required List<TargetDartFile> files,
  required bool dryRun,
}) {
  final changedFiles = <String>[];
  final migratedDeclarations = <Map<String, Object?>>[];
  final skippedDeclarations = <Map<String, Object?>>[];
  final skipReasonCounts = {
    for (final reason in DeclarationSkipReason.values) reason: 0,
  };
  final plannedFiles = <_PlannedFileMigration>[];

  for (final targetFile in files) {
    final source = targetFile.file.readAsStringSync();
    final plan = _planFileMigration(targetFile: targetFile, source: source);
    if (plan == null) {
      continue;
    }
    migratedDeclarations.addAll(plan.migratedDeclarations);
    for (final skippedDeclaration in plan.skippedDeclarations) {
      skippedDeclarations.add(skippedDeclaration.toJson());
      skipReasonCounts[skippedDeclaration.reason] =
          skipReasonCounts[skippedDeclaration.reason]! + 1;
    }
    if (plan.hasEdits) {
      changedFiles.add(targetFile.relativePath);
      plannedFiles.add(plan);
    }
  }

  for (final plan in plannedFiles) {
    _parseSource(
      plan.transformedSource,
      path: plan.targetFile.file.path,
      input: false,
    );
  }

  if (!dryRun) {
    for (final plan in plannedFiles) {
      plan.targetFile.file.writeAsStringSync(plan.transformedSource);
    }
  }

  return MigrationRunResult(
    changedFiles: changedFiles,
    migratedDeclarations: migratedDeclarations,
    skippedDeclarations: skippedDeclarations,
    transformCounts: {
      if (migratedDeclarations.isNotEmpty)
        primaryConstructorTransform: migratedDeclarations.length,
    },
    skipReasonCounts: {
      for (final reason in DeclarationSkipReason.values)
        if (skipReasonCounts[reason] != 0)
          reason.code: skipReasonCounts[reason]!,
    },
  );
}

_PlannedFileMigration? _planFileMigration({
  required TargetDartFile targetFile,
  required String source,
}) {
  final unit = _parseSource(source, path: targetFile.file.path, input: true);
  final edits = <SourceEdit>[];
  final migratedDeclarations = <Map<String, Object?>>[];
  final skippedDeclarations = <_SkippedDeclaration>[];

  for (final declaration
      in unit.unit.declarations.whereType<ClassDeclaration>()) {
    final skipReason = _primaryConstructorSkipReason(
      source: source,
      declaration: declaration,
    );
    if (skipReason != null) {
      skippedDeclarations.add(
        _SkippedDeclaration(
          path: targetFile.relativePath,
          declarationKind: 'class',
          declarationName: declaration.namePart.typeName.lexeme,
          transform: primaryConstructorTransform,
          offset: declaration.offset,
          reason: skipReason,
        ),
      );
      continue;
    }

    final classPlan = _planClassMigration(
      source: source,
      targetFile: targetFile,
      declaration: declaration,
    );
    if (classPlan == null) {
      continue;
    }
    edits.addAll(classPlan.edits);
    migratedDeclarations.add(classPlan.reportEntry);
  }

  if (edits.isEmpty && skippedDeclarations.isEmpty) {
    return null;
  }

  final transformedSource = edits.isEmpty
      ? source
      : applySourceEdits(source, edits);
  return _PlannedFileMigration(
    targetFile: targetFile,
    transformedSource: transformedSource,
    migratedDeclarations: migratedDeclarations,
    skippedDeclarations: skippedDeclarations,
    hasEdits: edits.isNotEmpty,
  );
}

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

bool _isSupportedConstructorBodyShape(FunctionBody body) {
  return body is EmptyFunctionBody || body is BlockFunctionBody;
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

ParseStringResult _parseSource(
  String source, {
  required String path,
  required bool input,
}) {
  final result = parseString(
    content: source,
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(
      flags: const ['primary-constructors'],
    ),
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) {
    final diagnostics = result.errors.map((error) => error.message).join('; ');
    throw MigrationFailure(
      'Failed to parse $path: $diagnostics',
      isInputParseFailure: input,
    );
  }
  return result;
}

String _sourceFor(String source, AstNode node) {
  return source.substring(node.offset, node.end);
}

String _lineIndentation(String source, int offset) {
  var start = offset;
  while (start > 0 && source.codeUnitAt(start - 1) != 10) {
    start--;
  }
  return source.substring(start, offset);
}

_FieldCommentMigration _fieldCommentMigration({
  required String source,
  required ClassDeclaration declaration,
  required FieldDeclaration member,
}) {
  if (_hasFollowingFieldComment(source, declaration, member)) {
    return const _FieldCommentMigration.ambiguous();
  }

  final comments = _leadingCommentTokens(member);
  if (comments.isEmpty) {
    return const _FieldCommentMigration.none();
  }
  if (!_isDirectCommentCluster(
    source,
    comments,
    member.firstTokenAfterCommentAndMetadata.offset,
  )) {
    return const _FieldCommentMigration.ambiguous();
  }

  final documentationComment =
      member.documentationComment ?? member.fields.documentationComment;
  if (documentationComment != null) {
    final documentationTokens = documentationComment.tokens;
    if (!_sameCommentTokens(comments, documentationTokens)) {
      return const _FieldCommentMigration.ambiguous();
    }
    return _FieldCommentMigration.direct(
      source: _commentSource(source, comments),
    );
  }

  if (!_isOrdinaryCommentCluster(comments) ||
      _isSharedOrdinaryFieldComment(source, declaration, member)) {
    return const _FieldCommentMigration.ambiguous();
  }
  return _FieldCommentMigration.direct(
    source: _commentSource(source, comments),
  );
}

List<Token> _leadingCommentTokens(AnnotatedNode node) {
  final comments = <Token>[];
  CommentToken? comment =
      node.firstTokenAfterCommentAndMetadata.precedingComments;
  while (comment != null) {
    comments.add(comment);
    comment = comment.next as CommentToken?;
  }
  return comments;
}

bool _sameCommentTokens(List<Token> left, List<Token> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index].offset != right[index].offset ||
        left[index].end != right[index].end) {
      return false;
    }
  }
  return true;
}

bool _isDirectCommentCluster(
  String source,
  List<Token> comments,
  int targetOffset,
) {
  for (var index = 0; index < comments.length - 1; index++) {
    if (!_hasSingleLineWhitespaceGap(
      source,
      comments[index].end,
      comments[index + 1].offset,
    )) {
      return false;
    }
  }
  return _hasSingleLineWhitespaceGap(source, comments.last.end, targetOffset);
}

bool _hasSingleLineWhitespaceGap(String source, int start, int end) {
  final gap = source.substring(start, end);
  return gap.trim().isEmpty && _lineBreakCount(gap) == 1;
}

int _lineBreakCount(String source) {
  var count = 0;
  for (var index = 0; index < source.length; index++) {
    if (source.codeUnitAt(index) == 10) {
      count++;
    }
  }
  return count;
}

bool _isOrdinaryCommentCluster(List<Token> comments) {
  if (comments.first.type == TokenType.SINGLE_LINE_COMMENT) {
    return comments.every(
      (comment) =>
          comment.type == TokenType.SINGLE_LINE_COMMENT &&
          !comment.lexeme.startsWith('///'),
    );
  }
  if (comments.first.type == TokenType.MULTI_LINE_COMMENT) {
    return comments.length == 1 && !comments.first.lexeme.startsWith('/**');
  }
  return false;
}

bool _isSharedOrdinaryFieldComment(
  String source,
  ClassDeclaration declaration,
  FieldDeclaration member,
) {
  final nextMember = _nextClassMember(declaration, member);
  if (nextMember is! FieldDeclaration ||
      _hasBlankLineBetween(source, member.end, nextMember.offset)) {
    return false;
  }
  final nextComments = _leadingCommentTokens(nextMember);
  return nextComments.isEmpty ||
      !_isDirectCommentCluster(
        source,
        nextComments,
        nextMember.firstTokenAfterCommentAndMetadata.offset,
      );
}

bool _hasFollowingFieldComment(
  String source,
  ClassDeclaration declaration,
  FieldDeclaration member,
) {
  final lineEnd = _lineEndOffset(source, member.end);
  if (_hasCommentMarker(source.substring(member.end, lineEnd))) {
    return true;
  }

  final nextMember = _nextClassMember(declaration, member);
  final nextOffset = nextMember == null
      ? declaration.body.end
      : _memberLeadingCommentOffset(nextMember);
  if (_hasCommentMarker(source.substring(lineEnd, nextOffset))) {
    return true;
  }

  if (nextMember is FieldDeclaration) {
    return false;
  }
  return nextMember != null &&
      _leadingCommentTokens(nextMember).any(_isOrdinaryCommentToken);
}

int _memberLeadingCommentOffset(ClassMember member) {
  final comments = _leadingCommentTokens(member);
  if (comments.isNotEmpty) {
    return comments.first.offset;
  }
  return member.offset;
}

bool _isOrdinaryCommentToken(Token comment) {
  return switch (comment.type) {
    TokenType.SINGLE_LINE_COMMENT => !comment.lexeme.startsWith('///'),
    TokenType.MULTI_LINE_COMMENT => !comment.lexeme.startsWith('/**'),
    _ => false,
  };
}

int _lineEndOffset(String source, int offset) {
  final lineEnd = source.indexOf('\n', offset);
  return lineEnd == -1 ? source.length : lineEnd;
}

bool _hasCommentMarker(String source) {
  return source.contains('//') || source.contains('/*');
}

bool _hasBlankLineBetween(String source, int start, int end) {
  return RegExp(r'\n[ \t\r]*\n').hasMatch(source.substring(start, end));
}

ClassMember? _nextClassMember(
  ClassDeclaration declaration,
  ClassMember member,
) {
  final members = declaration.body.members;
  for (var index = 0; index < members.length - 1; index++) {
    if (identical(members[index], member)) {
      return members[index + 1];
    }
  }
  return null;
}

String _commentSource(String source, List<Token> comments) {
  return source.substring(comments.first.offset, comments.last.end);
}

_SourceRange _commentRange(List<Token> comments) {
  return _SourceRange(
    comments.first.offset,
    comments.last.end - comments.first.offset,
  );
}

_SourceRange _memberRemovalRange(String source, ClassMember member) {
  final leadingCommentRange = member is FieldDeclaration
      ? _directFieldLeadingCommentRange(source, member)
      : null;
  var start = leadingCommentRange?.offset ?? member.offset;
  while (start > 0 && source.codeUnitAt(start - 1) != 10) {
    start--;
  }

  var end = member.end;
  while (end < source.length && source.codeUnitAt(end) != 10) {
    end++;
  }
  if (end < source.length) {
    end++;
  }
  while (end < source.length) {
    final nextLineEnd = source.indexOf('\n', end);
    final lineEnd = nextLineEnd == -1 ? source.length : nextLineEnd;
    if (source.substring(end, lineEnd).trim().isNotEmpty) {
      break;
    }
    end = lineEnd == source.length ? lineEnd : lineEnd + 1;
  }
  return _SourceRange(start, end - start);
}

_SourceRange? _directFieldLeadingCommentRange(
  String source,
  FieldDeclaration member,
) {
  final comments = _leadingCommentTokens(member);
  if (comments.isEmpty ||
      !_isDirectCommentCluster(
        source,
        comments,
        member.firstTokenAfterCommentAndMetadata.offset,
      )) {
    return null;
  }
  return _commentRange(comments);
}

class _ClassMigrationPlan {
  const _ClassMigrationPlan({required this.edits, required this.reportEntry});

  final List<SourceEdit> edits;
  final Map<String, Object?> reportEntry;
}

class _SkippedDeclaration {
  const _SkippedDeclaration({
    required this.path,
    required this.declarationKind,
    required this.declarationName,
    required this.transform,
    required this.offset,
    required this.reason,
  });

  final String path;
  final String declarationKind;
  final String declarationName;
  final String transform;
  final int offset;
  final DeclarationSkipReason reason;

  Map<String, Object?> toJson() {
    return {
      'path': path,
      'declarationKind': declarationKind,
      'declarationName': declarationName,
      'transform': transform,
      'offset': offset,
      'reason': reason.code,
      'message': reason.message,
    };
  }
}

class _ParameterMigrationPlan {
  const _ParameterMigrationPlan({
    this.edits = const [],
    this.removableFields = const [],
    this.fieldNames = const [],
    this.privateInitializerFieldNames = const [],
  });

  final List<SourceEdit> edits;
  final List<FieldDeclaration> removableFields;
  final List<String> fieldNames;
  final List<String> privateInitializerFieldNames;
}

class _ConstructorInitializerClassification {
  const _ConstructorInitializerClassification.plan(this.plan)
    : skipReason = null;

  const _ConstructorInitializerClassification.skip(this.skipReason)
    : plan = null;

  final _ConstructorInitializerPlan? plan;
  final DeclarationSkipReason? skipReason;
}

class _ConstructorInitializerPlan {
  const _ConstructorInitializerPlan({
    required this.privateFieldInitializersByName,
    required this.fieldInitializers,
    required this.retainedInitializers,
  });

  final Map<String, String> privateFieldInitializersByName;
  final List<_FieldInitializerMigration> fieldInitializers;
  final List<ConstructorInitializer> retainedInitializers;
}

class _FieldInitializerMigration {
  const _FieldInitializerMigration({
    required this.fieldName,
    required this.variable,
    required this.expression,
  });

  final String fieldName;
  final VariableDeclaration variable;
  final Expression expression;
}

class _FieldCommentMigration {
  const _FieldCommentMigration.none() : source = null, isAmbiguous = false;

  const _FieldCommentMigration.direct({required this.source})
    : isAmbiguous = false;

  const _FieldCommentMigration.ambiguous() : source = null, isAmbiguous = true;

  final String? source;
  final bool isAmbiguous;
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

class _EligibleField {
  const _EligibleField({
    required this.declaration,
    required this.variable,
    required this.typeSource,
    required this.declaringKeyword,
    this.leadingCommentSource,
  });

  final FieldDeclaration declaration;
  final VariableDeclaration variable;
  final String typeSource;
  final String declaringKeyword;
  final String? leadingCommentSource;
}

class _PlannedFileMigration {
  const _PlannedFileMigration({
    required this.targetFile,
    required this.transformedSource,
    required this.migratedDeclarations,
    required this.skippedDeclarations,
    required this.hasEdits,
  });

  final TargetDartFile targetFile;
  final String transformedSource;
  final List<Map<String, Object?>> migratedDeclarations;
  final List<_SkippedDeclaration> skippedDeclarations;
  final bool hasEdits;
}

class _SourceRange {
  const _SourceRange(this.offset, this.length);

  final int offset;
  final int length;
}
