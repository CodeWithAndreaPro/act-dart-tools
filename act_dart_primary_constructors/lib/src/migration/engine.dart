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
      final plan = _TargetFileDeclarationPlanner(
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

class _MigrationReportAccumulator {
  final _changedFiles = <String>[];
  final _migratedDeclarations = <MigratedDeclarationReport>[];
  final _skippedDeclarations = <SkippedDeclarationReport>[];
  final _transformCounts = <String, int>{};
  final _skipReasonCounts = {
    for (final reason in DeclarationSkipReason.values) reason: 0,
  };

  void addFilePlan(_PlannedFileMigration plan) {
    final facts = plan.reportFacts;
    _migratedDeclarations.addAll(facts.migratedDeclarations);
    _skippedDeclarations.addAll(facts.skippedDeclarations);
    for (final entry in facts.transformCounts.entries) {
      _transformCounts[entry.key] =
          (_transformCounts[entry.key] ?? 0) + entry.value;
    }
    for (final entry in facts.skipReasonCounts.entries) {
      _skipReasonCounts[entry.key] =
          _skipReasonCounts[entry.key]! + entry.value;
    }
    if (facts.changedFile case final changedFile?) {
      _changedFiles.add(changedFile);
    }
  }

  MigrationRunResult toResult() {
    return MigrationRunResult(
      changedFiles: _changedFiles,
      migratedDeclarations: _migratedDeclarations,
      skippedDeclarations: _skippedDeclarations,
      transformCounts: {
        for (final entry in _transformCounts.entries)
          if (entry.value != 0) entry.key: entry.value,
      },
      skipReasonCounts: {
        for (final reason in DeclarationSkipReason.values)
          if (_skipReasonCounts[reason] != 0)
            reason: _skipReasonCounts[reason]!,
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
