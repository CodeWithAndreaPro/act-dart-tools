part of 'primary_constructors.dart';

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

    final primaryTargetDecision = _decidePrimaryConstructorTarget(
      generativeConstructors,
    );
    final _PrimaryConstructorTarget primaryTarget;
    switch (primaryTargetDecision) {
      case _PlannedPrimaryConstructorTarget(:final target):
        primaryTarget = target;
      case _SkippedPrimaryConstructorTarget(:final reason):
        return _SkippedEnumPrimaryConstructor(reason);
      case _NoPrimaryConstructorTarget():
        return const _NoOpEnumPrimaryConstructor();
    }

    final constructor = primaryTarget.constructor;
    if (_hasNamedPrimaryConstructorConflict(constructor)) {
      return const _SkippedEnumPrimaryConstructor(
        DeclarationSkipReason.primaryConstructorConflict,
      );
    }

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
    if (constructor.body is BlockFunctionBody) {
      return const _SkippedEnumPrimaryConstructor(
        DeclarationSkipReason.unsupportedConstructorBody,
      );
    }

    return _MigratedEnumPrimaryConstructor(
      _buildMigrationPlan(
        constructor: constructor,
        realizationPlan: realizationPlan,
      ),
    );
  }

  _PrimaryConstructorTargetDecision _decidePrimaryConstructorTarget(
    List<ConstructorDeclaration> generativeConstructors,
  ) {
    final nonRedirectingConstructors = generativeConstructors
        .where((constructor) => !_isRedirectingConstructor(constructor))
        .toList();
    if (nonRedirectingConstructors.isEmpty) {
      return const _NoPrimaryConstructorTarget();
    }
    if (nonRedirectingConstructors.length > 1) {
      return const _SkippedPrimaryConstructorTarget(
        DeclarationSkipReason.multipleConstructors,
      );
    }

    return _PlannedPrimaryConstructorTarget(
      _PrimaryConstructorTarget(constructor: nonRedirectingConstructors.single),
    );
  }

  bool _hasNamedPrimaryConstructorConflict(ConstructorDeclaration constructor) {
    final name = _namedPrimaryConstructorBasename(constructor);
    if (name == null) {
      return false;
    }
    for (final member in declaration.body.members) {
      if (identical(member, constructor)) {
        continue;
      }
      if (member is MethodDeclaration &&
          member.isStatic &&
          member.name.lexeme == name) {
        return true;
      }
      if (member is FieldDeclaration && member.isStatic) {
        for (final variable in member.fields.variables) {
          if (variable.name.lexeme == name) {
            return true;
          }
        }
      }
      if (member is ConstructorDeclaration && member.name?.lexeme == name) {
        return true;
      }
    }
    return false;
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
      SourceEdit.insert(
        declaration.namePart.end,
        '${_primaryConstructorSuffix(constructor)}$primaryParameters',
      ),
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
