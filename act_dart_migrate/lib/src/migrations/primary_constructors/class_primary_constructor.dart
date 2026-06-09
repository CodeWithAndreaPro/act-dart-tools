part of 'primary_constructors.dart';

class _ClassPrimaryConstructorPlanner {
  const _ClassPrimaryConstructorPlanner({
    required this.source,
    required this.targetFile,
    required this.declaration,
  });

  final String source;
  final TargetDartFile targetFile;
  final ClassDeclaration declaration;

  _ClassPrimaryConstructorDecision decide() {
    if (declaration.namePart is PrimaryConstructorDeclaration) {
      return const _NoOpClassPrimaryConstructor();
    }

    final constructors = declaration.body.members
        .whereType<ConstructorDeclaration>()
        .toList();
    if (constructors.isEmpty) {
      return const _NoOpClassPrimaryConstructor();
    }

    final generativeConstructors = constructors
        .where((constructor) => constructor.factoryKeyword == null)
        .toList();
    if (generativeConstructors.isEmpty) {
      return const _NoOpClassPrimaryConstructor();
    }

    final unnamedConstructors = generativeConstructors
        .where(_isUnnamedConstructor)
        .toList();
    if (unnamedConstructors.isEmpty) {
      return const _NoOpClassPrimaryConstructor();
    }
    if (unnamedConstructors.length > 1) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.multipleConstructors,
      );
    }

    final constructor = unnamedConstructors.single;
    if (constructor.externalKeyword != null) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.externalConstructor,
      );
    }
    if (constructor.metadata.isNotEmpty) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.constructorMetadata,
      );
    }
    if (constructor.documentationComment != null) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.constructorComment,
      );
    }
    if (constructor.redirectedConstructor != null) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.redirectingConstructor,
      );
    }
    final realizationDecision = _ConstructorRealizationPlanner(
      source: source,
      bodyInfo: _classBodyInfo(declaration),
      constructor: constructor,
    ).decide();
    final _ConstructorRealizationPlan realizationPlan;
    switch (realizationDecision) {
      case _PlannedConstructorRealization(:final plan):
        realizationPlan = plan;
      case _SkippedConstructorRealization(:final reason):
        return _SkippedClassPrimaryConstructor(reason);
    }

    if (generativeConstructors.any(
      (constructor) =>
          constructor.externalKeyword == null &&
          constructor != unnamedConstructors.single &&
          !_isUnnamedConstructor(constructor) &&
          !_isRedirectingConstructor(constructor),
    )) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.namedConstructor,
      );
    }
    if (constructor.parameters.parameters.isEmpty &&
        constructor.constKeyword == null &&
        declaration.body.members.length != 1 &&
        !realizationPlan.primaryBodyRequired) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.emptyNonConstConstructorWithMembers,
      );
    }

    return _MigratedClassPrimaryConstructor(
      _buildMigrationPlan(
        constructor: constructor,
        realizationPlan: realizationPlan,
      ),
    );
  }

  _ClassMigrationPlan _buildMigrationPlan({
    required ConstructorDeclaration constructor,
    required _ConstructorRealizationPlan realizationPlan,
  }) {
    final constructorParameters = constructor.parameters.parameters;
    final parameterEdits = <SourceEdit>[];
    final primaryBodyRequired = realizationPlan.primaryBodyRequired;
    final removableMembers = <ClassMember>{
      if (!primaryBodyRequired) constructor,
    };
    final parametersRange = _rangeFor(constructor.parameters);

    for (final parameterPlan in realizationPlan.parameterPlans) {
      parameterEdits.addAll(parameterPlan.edits);
      removableMembers.addAll(parameterPlan.removableFields);
    }

    final primaryParameters =
        constructorParameters.isEmpty &&
            constructor.constKeyword == null &&
            !primaryBodyRequired
        ? null
        : applySourceEditsInRange(source, parametersRange, parameterEdits);
    final edits = <SourceEdit>[
      if (constructor.constKeyword != null)
        SourceEdit.insert(declaration.classKeyword.end, ' const'),
      if (primaryParameters != null)
        SourceEdit.insert(declaration.namePart.end, primaryParameters),
      ...realizationPlan.fieldInitializerEdits,
    ];
    final bodyRewritePlan =
        _ClassBodyRewritePlanner(
          source: source,
          declaration: declaration,
          constructor: constructor,
        ).plan(
          removableMembers: removableMembers,
          primaryBodySource: realizationPlan.primaryBodySource,
        );
    edits.addAll(bodyRewritePlan.edits);

    return _ClassMigrationPlan(
      edits: edits,
      emptyClassBodyRewrite: bodyRewritePlan.emptyClassBodyRewrite,
      emptyClassBodySkipReason: bodyRewritePlan.emptyClassBodySkipReason,
      migratedDeclaration: MigratedDeclarationReport(
        path: targetFile.relativePath,
        declarationKind: 'class',
        declarationName: declaration.namePart.typeName.lexeme,
        transform: primaryConstructorTransform,
        offset: declaration.offset,
      ),
    );
  }
}

sealed class _ClassPrimaryConstructorDecision {
  const _ClassPrimaryConstructorDecision();
}

final class _MigratedClassPrimaryConstructor
    extends _ClassPrimaryConstructorDecision {
  const _MigratedClassPrimaryConstructor(this.plan);

  final _ClassMigrationPlan plan;
}

final class _SkippedClassPrimaryConstructor
    extends _ClassPrimaryConstructorDecision {
  const _SkippedClassPrimaryConstructor(this.reason);

  final DeclarationSkipReason reason;
}

final class _NoOpClassPrimaryConstructor
    extends _ClassPrimaryConstructorDecision {
  const _NoOpClassPrimaryConstructor();
}

bool _isUnnamedConstructor(ConstructorDeclaration constructor) {
  return constructor.name == null && constructor.period == null;
}

bool _isRedirectingConstructor(ConstructorDeclaration constructor) {
  return constructor.redirectedConstructor != null ||
      constructor.initializers.any(
        (initializer) => initializer is RedirectingConstructorInvocation,
      );
}
