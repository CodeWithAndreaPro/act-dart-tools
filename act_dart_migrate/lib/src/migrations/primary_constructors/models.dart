part of 'primary_constructors.dart';

class _ClassMigrationPlan {
  const _ClassMigrationPlan({
    required this.edits,
    required this.migratedDeclaration,
    this.emptyClassBodyRewrite,
    this.emptyClassBodySkipReason,
  });

  final List<SourceEdit> edits;
  final _EmptyClassBodyRewriteIntent? emptyClassBodyRewrite;
  final DeclarationSkipReason? emptyClassBodySkipReason;
  final MigratedDeclarationReport migratedDeclaration;

  List<SourceEdit> get sourceEdits => [
    ...edits,
    if (emptyClassBodyRewrite case final rewrite?) rewrite.toEdit(),
  ];
}

class _ClassBodyRewritePlan {
  const _ClassBodyRewritePlan({
    required this.edits,
    this.emptyClassBodyRewrite,
    this.emptyClassBodySkipReason,
  });

  final List<SourceEdit> edits;
  final _EmptyClassBodyRewriteIntent? emptyClassBodyRewrite;
  final DeclarationSkipReason? emptyClassBodySkipReason;

  List<SourceEdit> get sourceEdits => [
    ...edits,
    if (emptyClassBodyRewrite case final rewrite?) rewrite.toEdit(),
  ];
}

class _EnumMigrationPlan {
  const _EnumMigrationPlan({
    required this.edits,
    required this.migratedDeclaration,
  });

  final List<SourceEdit> edits;
  final MigratedDeclarationReport migratedDeclaration;

  List<SourceEdit> get sourceEdits => edits;
}

class _DeclarationBodyInfo {
  const _DeclarationBodyInfo({required this.members, required this.bodyEnd});

  final NodeList<ClassMember> members;
  final int bodyEnd;
}

class _EmptyClassBodyRewriteIntent {
  const _EmptyClassBodyRewriteIntent({required this.declaration});

  final ClassDeclaration declaration;

  SourceEdit toEdit() => SourceEdit.replace(_rangeFor(declaration.body), ';');
}

class _ParameterMigrationPlan {
  const _ParameterMigrationPlan({
    this.edits = const [],
    this.removableFields = const [],
  });

  final List<SourceEdit> edits;
  final List<FieldDeclaration> removableFields;
}

class _ConstructorInitializationPlan {
  const _ConstructorInitializationPlan({
    required this.privateFieldInitializersByName,
    required this.fieldInitializers,
    required this.primaryBodySource,
    required this.hasRetainedSuperConstructorInitializer,
  });

  final Map<String, String> privateFieldInitializersByName;
  final List<_FieldInitializerMigration> fieldInitializers;
  final String? primaryBodySource;
  final bool hasRetainedSuperConstructorInitializer;

  bool get primaryBodyRequired => primaryBodySource != null;
}

class _ConstructorRealizationPlan {
  const _ConstructorRealizationPlan({
    required this.parameterPlans,
    required this.fieldInitializerEdits,
    required this.primaryBodySource,
    required this.hasRetainedSuperConstructorInitializer,
  });

  final List<_ParameterMigrationPlan> parameterPlans;
  final List<SourceEdit> fieldInitializerEdits;
  final String? primaryBodySource;
  final bool hasRetainedSuperConstructorInitializer;

  bool get primaryBodyRequired => primaryBodySource != null;
}

class _FieldInitializerMigration {
  const _FieldInitializerMigration({
    required this.fieldName,
    required this.initializerOffset,
    required this.variable,
    required this.expression,
  });

  final String fieldName;
  final int initializerOffset;
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

class _PlannedFileMigration {
  const _PlannedFileMigration({
    required this.targetFile,
    required this.transformedSource,
    required this.reportFacts,
  });

  final TargetDartFile targetFile;
  final String transformedSource;
  final _FileMigrationReportFacts reportFacts;

  bool get hasEdits => reportFacts.changedFile != null;
}

class _FileMigrationReportFacts {
  const _FileMigrationReportFacts({
    required this.changedFile,
    required this.migratedDeclarations,
    required this.skippedDeclarations,
    required this.transformCounts,
    required this.skipReasonCounts,
  });

  final String? changedFile;
  final List<MigratedDeclarationReport> migratedDeclarations;
  final List<SkippedDeclarationReport> skippedDeclarations;
  final Map<String, int> transformCounts;
  final Map<String, int> skipReasonCounts;
}

class _DeclarationMigrationPlan {
  const _DeclarationMigrationPlan({
    this.edits = const [],
    this.migratedDeclarations = const [],
    this.skippedDeclarations = const [],
  });

  final List<SourceEdit> edits;
  final List<MigratedDeclarationReport> migratedDeclarations;
  final List<SkippedDeclarationReport> skippedDeclarations;
}
