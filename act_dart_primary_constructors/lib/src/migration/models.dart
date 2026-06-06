part of '../migration.dart';

class MigrationFailure implements Exception {
  const MigrationFailure(this.message, {required this.isInputParseFailure});

  final String message;
  final bool isInputParseFailure;

  @override
  String toString() => 'MigrationFailure: $message';
}

class _ClassMigrationPlan {
  const _ClassMigrationPlan({
    required this.edits,
    required this.migratedDeclaration,
  });

  final List<SourceEdit> edits;
  final MigratedDeclarationReport migratedDeclaration;
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
  });

  final Map<String, String> privateFieldInitializersByName;
  final List<_FieldInitializerMigration> fieldInitializers;
  final String? primaryBodySource;

  bool get primaryBodyRequired => primaryBodySource != null;
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
  final Map<DeclarationSkipReason, int> skipReasonCounts;
}

class _DeclarationMigrationPlan {
  const _DeclarationMigrationPlan({
    this.edits = const [],
    this.migratedDeclaration,
    this.skippedDeclaration,
  });

  final List<SourceEdit> edits;
  final MigratedDeclarationReport? migratedDeclaration;
  final SkippedDeclarationReport? skippedDeclaration;
}
