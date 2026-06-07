part of '../migration.dart';

final class _EnumPrimaryConstructorPlanner {
  const _EnumPrimaryConstructorPlanner({
    required this.source,
    required this.targetFile,
    required this.declaration,
  });

  final String source;
  final TargetDartFile targetFile;
  final EnumDeclaration declaration;

  _EnumPrimaryConstructorDecision decide() {
    if (declaration.namePart is PrimaryConstructorDeclaration) {
      return const _NoOpEnumPrimaryConstructor();
    }

    final constructors = declaration.body.members
        .whereType<ConstructorDeclaration>()
        .toList();
    if (constructors.isEmpty) {
      return const _NoOpEnumPrimaryConstructor();
    }

    final generativeConstructors = constructors
        .where((constructor) => constructor.factoryKeyword == null)
        .toList();
    if (generativeConstructors.isEmpty) {
      return const _NoOpEnumPrimaryConstructor();
    }

    final unnamedConstructors = generativeConstructors
        .where(_isUnnamedConstructor)
        .toList();
    if (unnamedConstructors.isEmpty) {
      return const _NoOpEnumPrimaryConstructor();
    }
    if (unnamedConstructors.length > 1) {
      return const _SkippedEnumPrimaryConstructor(
        DeclarationSkipReason.multipleConstructors,
      );
    }

    final constructor = unnamedConstructors.single;
    if (constructor.externalKeyword != null) {
      return const _SkippedEnumPrimaryConstructor(
        DeclarationSkipReason.externalConstructor,
      );
    }
    if (constructor.metadata.isNotEmpty) {
      return const _SkippedEnumPrimaryConstructor(
        DeclarationSkipReason.constructorMetadata,
      );
    }
    if (constructor.documentationComment != null) {
      return const _SkippedEnumPrimaryConstructor(
        DeclarationSkipReason.constructorComment,
      );
    }
    if (constructor.redirectedConstructor != null) {
      return const _SkippedEnumPrimaryConstructor(
        DeclarationSkipReason.redirectingConstructor,
      );
    }

    final bodyInfo = _enumBodyInfo(declaration);
    final realizationDecision = _ConstructorRealizationPlanner(
      source: source,
      bodyInfo: bodyInfo,
      constructor: constructor,
    ).decide();
    final _ConstructorRealizationPlan realizationPlan;
    switch (realizationDecision) {
      case _PlannedConstructorRealization(:final plan):
        realizationPlan = plan;
      case _SkippedConstructorRealization(:final reason):
        return _SkippedEnumPrimaryConstructor(reason);
    }

    if (generativeConstructors.any(
      (constructor) =>
          constructor.externalKeyword == null &&
          constructor != unnamedConstructors.single &&
          !_isUnnamedConstructor(constructor),
    )) {
      return const _SkippedEnumPrimaryConstructor(
        DeclarationSkipReason.namedConstructor,
      );
    }

    return _MigratedEnumPrimaryConstructor(
      _buildMigrationPlan(
        constructor: constructor,
        realizationPlan: realizationPlan,
      ),
    );
  }

  _EnumMigrationPlan _buildMigrationPlan({
    required ConstructorDeclaration constructor,
    required _ConstructorRealizationPlan realizationPlan,
  }) {
    final parametersRange = _rangeFor(constructor.parameters);
    final parameterEdits = <SourceEdit>[];
    final removableMembers = <ClassMember>{
      if (!realizationPlan.primaryBodyRequired) constructor,
    };

    for (final parameterPlan in realizationPlan.parameterPlans) {
      parameterEdits.addAll(parameterPlan.edits);
      removableMembers.addAll(parameterPlan.removableFields);
    }

    final primaryParameters = applySourceEditsInRange(
      source,
      parametersRange,
      parameterEdits,
    );
    final edits = <SourceEdit>[
      SourceEdit.insert(declaration.namePart.end, primaryParameters),
      ...realizationPlan.fieldInitializerEdits,
      ..._enumBodyEdits(
        constructor: constructor,
        removableMembers: removableMembers,
        primaryBodySource: realizationPlan.primaryBodySource,
      ),
    ];

    validateSourceEdits(source, edits);
    return _EnumMigrationPlan(
      edits: edits,
      migratedDeclaration: MigratedDeclarationReport(
        path: targetFile.relativePath,
        declarationKind: 'enum',
        declarationName: declaration.namePart.typeName.lexeme,
        transform: primaryConstructorTransform,
        offset: declaration.offset,
      ),
    );
  }

  List<SourceEdit> _enumBodyEdits({
    required ConstructorDeclaration constructor,
    required Set<ClassMember> removableMembers,
    required String? primaryBodySource,
  }) {
    final removalRanges = [
      for (final member in removableMembers)
        _memberRemovalRange(source, member),
    ];
    final edits = [
      for (final range in removalRanges) SourceEdit.delete(range),
      if (primaryBodySource != null)
        SourceEdit.replace(
          _memberRemovalRange(source, constructor),
          primaryBodySource,
        ),
    ];
    validateSourceEdits(source, edits);
    return edits;
  }
}

sealed class _EnumPrimaryConstructorDecision {
  const _EnumPrimaryConstructorDecision();
}

final class _MigratedEnumPrimaryConstructor
    extends _EnumPrimaryConstructorDecision {
  const _MigratedEnumPrimaryConstructor(this.plan);

  final _EnumMigrationPlan plan;
}

final class _SkippedEnumPrimaryConstructor
    extends _EnumPrimaryConstructorDecision {
  const _SkippedEnumPrimaryConstructor(this.reason);

  final DeclarationSkipReason reason;
}

final class _NoOpEnumPrimaryConstructor
    extends _EnumPrimaryConstructorDecision {
  const _NoOpEnumPrimaryConstructor();
}
