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
    final edits = <SourceEdit>[];
    final migratedDeclarations = <_MigratedDeclaration>[];
    final skippedDeclarations = <_SkippedDeclaration>[];

    for (final declaration in parseResult.unit.declarations) {
      final plan = _planDeclaration(declaration);
      edits.addAll(plan.edits);
      if (plan.migratedDeclaration case final migratedDeclaration?) {
        migratedDeclarations.add(migratedDeclaration);
      }
      if (plan.skippedDeclaration case final skippedDeclaration?) {
        skippedDeclarations.add(skippedDeclaration);
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

  _DeclarationMigrationPlan _planDeclaration(
    CompilationUnitMember declaration,
  ) {
    if (declaration is ClassDeclaration) {
      return _planClassPrimaryConstructor(declaration);
    }
    return const _DeclarationMigrationPlan();
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
