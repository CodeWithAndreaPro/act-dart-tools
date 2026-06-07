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
    if (declaration is EnumDeclaration) {
      return _planEnumDeclaration(declaration);
    }
    return const _DeclarationMigrationPlan();
  }

  _DeclarationMigrationPlan _planClassDeclaration(
    ClassDeclaration declaration,
  ) {
    final primaryConstructorPlan = _planClassPrimaryConstructor(declaration);
    final emptyClassBodyPlan = _planStandaloneEmptyClassBody(declaration);
    return _DeclarationMigrationPlan(
      edits: [...primaryConstructorPlan.edits, ...emptyClassBodyPlan.edits],
      migratedDeclarations: [
        ...primaryConstructorPlan.migratedDeclarations,
        ...emptyClassBodyPlan.migratedDeclarations,
      ],
      skippedDeclarations: [
        ...primaryConstructorPlan.skippedDeclarations,
        ...emptyClassBodyPlan.skippedDeclarations,
      ],
    );
  }

  _DeclarationMigrationPlan _planStandaloneEmptyClassBody(
    ClassDeclaration declaration,
  ) {
    final emptyClassBodyPlanner = _EmptyClassBodyPlanner(
      source: source,
      declaration: declaration,
    );
    return switch (emptyClassBodyPlanner.decide()) {
      _MigratedEmptyClassBody(:final rewrite) => _DeclarationMigrationPlan(
        edits: [rewrite.toEdit()],
        migratedDeclarations: [_emptyClassBodyMigratedReport(declaration)],
      ),
      _SkippedEmptyClassBody(:final reason) => _DeclarationMigrationPlan(
        skippedDeclarations: [
          _emptyClassBodySkippedReport(declaration, reason),
        ],
      ),
      _NoOpEmptyClassBody() => const _DeclarationMigrationPlan(),
    };
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
          edits: plan.sourceEdits,
          migratedDeclarations: [
            plan.migratedDeclaration,
            if (plan.emptyClassBodyRewrite != null)
              _emptyClassBodyMigratedReport(declaration),
          ],
          skippedDeclarations: [
            if (plan.emptyClassBodySkipReason case final reason?)
              _emptyClassBodySkippedReport(declaration, reason),
          ],
        ),
      _SkippedClassPrimaryConstructor(:final reason) =>
        _DeclarationMigrationPlan(
          skippedDeclarations: [
            SkippedDeclarationReport(
              path: targetFile.relativePath,
              declarationKind: 'class',
              declarationName: declaration.namePart.typeName.lexeme,
              transform: primaryConstructorTransform,
              offset: declaration.offset,
              reason: reason,
            ),
          ],
        ),
      _NoOpClassPrimaryConstructor() => const _DeclarationMigrationPlan(),
    };
  }

  _DeclarationMigrationPlan _planEnumDeclaration(EnumDeclaration declaration) {
    final enumPlanner = _EnumPrimaryConstructorPlanner(
      source: source,
      targetFile: targetFile,
      declaration: declaration,
    );
    return switch (enumPlanner.decide()) {
      _MigratedEnumPrimaryConstructor(:final plan) => _DeclarationMigrationPlan(
        edits: plan.sourceEdits,
        migratedDeclarations: [plan.migratedDeclaration],
      ),
      _SkippedEnumPrimaryConstructor(:final reason) =>
        _DeclarationMigrationPlan(
          skippedDeclarations: [
            SkippedDeclarationReport(
              path: targetFile.relativePath,
              declarationKind: 'enum',
              declarationName: declaration.namePart.typeName.lexeme,
              transform: primaryConstructorTransform,
              offset: declaration.offset,
              reason: reason,
            ),
          ],
        ),
      _NoOpEnumPrimaryConstructor() => const _DeclarationMigrationPlan(),
    };
  }

  MigratedDeclarationReport _emptyClassBodyMigratedReport(
    ClassDeclaration declaration,
  ) {
    return MigratedDeclarationReport(
      path: targetFile.relativePath,
      declarationKind: 'class',
      declarationName: declaration.namePart.typeName.lexeme,
      transform: emptyClassBodyTransform,
      offset: declaration.offset,
    );
  }

  SkippedDeclarationReport _emptyClassBodySkippedReport(
    ClassDeclaration declaration,
    DeclarationSkipReason reason,
  ) {
    return SkippedDeclarationReport(
      path: targetFile.relativePath,
      declarationKind: 'class',
      declarationName: declaration.namePart.typeName.lexeme,
      transform: emptyClassBodyTransform,
      offset: declaration.offset,
      reason: reason,
    );
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
  final _migratedDeclarations = <MigratedDeclarationReport>[];
  final _skippedDeclarations = <SkippedDeclarationReport>[];

  void addDeclarationPlan(_DeclarationMigrationPlan plan) {
    _edits.addAll(plan.edits);
    _migratedDeclarations.addAll(plan.migratedDeclarations);
    _skippedDeclarations.addAll(plan.skippedDeclarations);
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
