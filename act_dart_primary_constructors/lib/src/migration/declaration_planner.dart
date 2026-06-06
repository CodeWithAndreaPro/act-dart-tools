part of '../migration.dart';

class _TargetFileDeclarationPlanner {
  const _TargetFileDeclarationPlanner({
    required this.targetFile,
    required this.source,
  });

  final TargetDartFile targetFile;
  final String source;

  _PlannedFileMigration? plan() {
    final parseResult = _parseSource(
      source,
      path: targetFile.file.path,
      input: true,
    );
    final filePlanBuilder = _TargetFileMigrationPlanBuilder(
      targetFile: targetFile,
      source: source,
    );

    for (final declaration in parseResult.unit.declarations) {
      final plan = _planDeclaration(declaration);
      filePlanBuilder.addDeclarationPlan(plan);
    }

    return filePlanBuilder.build();
  }

  _DeclarationMigrationPlan _planDeclaration(
    CompilationUnitMember declaration,
  ) {
    if (declaration is ClassDeclaration) {
      return _planClassDeclaration(declaration);
    }
    return const _DeclarationMigrationPlan();
  }

  _DeclarationMigrationPlan _planClassDeclaration(
    ClassDeclaration declaration,
  ) {
    return _planClassPrimaryConstructor(declaration);
  }

  _DeclarationMigrationPlan _planClassPrimaryConstructor(
    ClassDeclaration declaration,
  ) {
    final classPlanner = _ClassPrimaryConstructorPlanner(
      source: source,
      targetFile: targetFile,
      declaration: declaration,
    );
    return switch (classPlanner.decide()) {
      _MigratedClassPrimaryConstructor(:final plan) =>
        _DeclarationMigrationPlan(
          edits: plan.edits,
          migratedDeclaration: plan.migratedDeclaration,
        ),
      _SkippedClassPrimaryConstructor(:final reason) =>
        _DeclarationMigrationPlan(
          skippedDeclaration: _SkippedDeclaration(
            path: targetFile.relativePath,
            declarationKind: 'class',
            declarationName: declaration.namePart.typeName.lexeme,
            transform: primaryConstructorTransform,
            offset: declaration.offset,
            reason: reason,
          ),
        ),
      _NoOpClassPrimaryConstructor() => const _DeclarationMigrationPlan(),
    };
  }
}

class _TargetFileMigrationPlanBuilder {
  _TargetFileMigrationPlanBuilder({
    required this.targetFile,
    required this.source,
  });

  final TargetDartFile targetFile;
  final String source;
  final _edits = <SourceEdit>[];
  final _migratedDeclarations = <_MigratedDeclaration>[];
  final _skippedDeclarations = <_SkippedDeclaration>[];

  void addDeclarationPlan(_DeclarationMigrationPlan plan) {
    _edits.addAll(plan.edits);
    if (plan.migratedDeclaration case final migratedDeclaration?) {
      _migratedDeclarations.add(migratedDeclaration);
    }
    if (plan.skippedDeclaration case final skippedDeclaration?) {
      _skippedDeclarations.add(skippedDeclaration);
    }
  }

  _PlannedFileMigration? build() {
    if (_edits.isEmpty && _skippedDeclarations.isEmpty) {
      return null;
    }

    final hasEdits = _edits.isNotEmpty;
    final transformedSource = hasEdits
        ? applySourceEdits(source, _edits)
        : source;
    return _PlannedFileMigration(
      targetFile: targetFile,
      transformedSource: transformedSource,
      reportFacts: _buildReportFacts(hasEdits: hasEdits),
    );
  }

  _FileMigrationReportFacts _buildReportFacts({required bool hasEdits}) {
    final transformCounts = <String, int>{};
    for (final declaration in _migratedDeclarations) {
      transformCounts[declaration.transform] =
          (transformCounts[declaration.transform] ?? 0) + 1;
    }

    final skipReasonCounts = {
      for (final reason in DeclarationSkipReason.values) reason: 0,
    };
    for (final declaration in _skippedDeclarations) {
      skipReasonCounts[declaration.reason] =
          skipReasonCounts[declaration.reason]! + 1;
    }

    return _FileMigrationReportFacts(
      changedFile: hasEdits ? targetFile.relativePath : null,
      migratedDeclarations: _migratedDeclarations,
      skippedDeclarations: _skippedDeclarations,
      transformCounts: transformCounts,
      skipReasonCounts: skipReasonCounts,
    );
  }
}
