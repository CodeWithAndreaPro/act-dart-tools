part of '../migration.dart';

MigrationRunResult migrateTargetPackageFiles({
  required List<TargetDartFile> files,
  required bool dryRun,
}) {
  return _MigrationEngine(files: files, dryRun: dryRun).run();
}

class _MigrationEngine {
  _MigrationEngine({required this.files, required this.dryRun});

  final List<TargetDartFile> files;
  final bool dryRun;

  MigrationRunResult run() {
    final report = _MigrationReportAccumulator();
    final plannedFiles = <_PlannedFileMigration>[];

    for (final targetFile in files) {
      final source = targetFile.file.readAsStringSync();
      final plan = _FileMigrationPlanner(
        targetFile: targetFile,
        source: source,
      ).plan();
      if (plan == null) {
        continue;
      }
      report.addFilePlan(plan);
      if (plan.hasEdits) {
        plannedFiles.add(plan);
      }
    }

    _validateTransformedSources(plannedFiles);

    if (!dryRun) {
      _writePlannedFiles(plannedFiles);
    }

    return report.toResult();
  }

  void _validateTransformedSources(List<_PlannedFileMigration> plannedFiles) {
    for (final plan in plannedFiles) {
      _parseSource(
        plan.transformedSource,
        path: plan.targetFile.file.path,
        input: false,
      );
    }
  }

  void _writePlannedFiles(List<_PlannedFileMigration> plannedFiles) {
    for (final plan in plannedFiles) {
      plan.targetFile.file.writeAsStringSync(plan.transformedSource);
    }
  }
}

class _FileMigrationPlanner {
  const _FileMigrationPlanner({required this.targetFile, required this.source});

  final TargetDartFile targetFile;
  final String source;

  _PlannedFileMigration? plan() {
    final unit = _parseSource(source, path: targetFile.file.path, input: true);
    final edits = <SourceEdit>[];
    final migratedDeclarations = <_MigratedDeclaration>[];
    final skippedDeclarations = <_SkippedDeclaration>[];

    for (final declaration
        in unit.unit.declarations.whereType<ClassDeclaration>()) {
      final classPlanner = _ClassPrimaryConstructorPlanner(
        source: source,
        targetFile: targetFile,
        declaration: declaration,
      );
      switch (classPlanner.decide()) {
        case _MigratedClassPrimaryConstructor(:final plan):
          edits.addAll(plan.edits);
          migratedDeclarations.add(plan.migratedDeclaration);
        case _SkippedClassPrimaryConstructor(:final reason):
          skippedDeclarations.add(
            _SkippedDeclaration(
              path: targetFile.relativePath,
              declarationKind: 'class',
              declarationName: declaration.namePart.typeName.lexeme,
              transform: primaryConstructorTransform,
              offset: declaration.offset,
              reason: reason,
            ),
          );
        case _NoOpClassPrimaryConstructor():
          continue;
      }
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
}

class _MigrationReportAccumulator {
  final _changedFiles = <String>[];
  final _migratedDeclarations = <_MigratedDeclaration>[];
  final _skippedDeclarations = <_SkippedDeclaration>[];
  final _transformCounts = <String, int>{};
  final _skipReasonCounts = {
    for (final reason in DeclarationSkipReason.values) reason: 0,
  };

  void addFilePlan(_PlannedFileMigration plan) {
    _migratedDeclarations.addAll(plan.migratedDeclarations);
    for (final migratedDeclaration in plan.migratedDeclarations) {
      _transformCounts[migratedDeclaration.transform] =
          (_transformCounts[migratedDeclaration.transform] ?? 0) + 1;
    }
    for (final skippedDeclaration in plan.skippedDeclarations) {
      _skippedDeclarations.add(skippedDeclaration);
      _skipReasonCounts[skippedDeclaration.reason] =
          _skipReasonCounts[skippedDeclaration.reason]! + 1;
    }
    if (plan.hasEdits) {
      _changedFiles.add(plan.targetFile.relativePath);
    }
  }

  MigrationRunResult toResult() {
    return MigrationRunResult(
      changedFiles: _changedFiles,
      migratedDeclarations: [
        for (final declaration in _migratedDeclarations) declaration.toJson(),
      ],
      skippedDeclarations: [
        for (final declaration in _skippedDeclarations) declaration.toJson(),
      ],
      transformCounts: {
        if ((_transformCounts[primaryConstructorTransform] ?? 0) != 0)
          primaryConstructorTransform:
              _transformCounts[primaryConstructorTransform]!,
      },
      skipReasonCounts: {
        for (final reason in DeclarationSkipReason.values)
          if (_skipReasonCounts[reason] != 0)
            reason.code: _skipReasonCounts[reason]!,
      },
    );
  }
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
