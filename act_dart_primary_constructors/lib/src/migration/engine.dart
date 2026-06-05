part of '../migration.dart';

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
