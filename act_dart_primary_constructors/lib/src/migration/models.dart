part of '../migration.dart';

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
