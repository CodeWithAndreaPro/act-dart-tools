part of 'primary_constructors.dart';

class _ClassPrimaryConstructorPlanner {
  const _ClassPrimaryConstructorPlanner({
    required this.source,
    required this.targetFile,
    required this.declaration,
    required this.skipSuperConstructorInitializers,
  });

  final String source;
  final TargetDartFile targetFile;
  final ClassDeclaration declaration;
  final bool skipSuperConstructorInitializers;

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

    final primaryTargetDecision = _decidePrimaryConstructorTarget(
      generativeConstructors,
    );
    final _PrimaryConstructorTarget primaryTarget;
    switch (primaryTargetDecision) {
      case _PlannedPrimaryConstructorTarget(:final target):
        primaryTarget = target;
      case _SkippedPrimaryConstructorTarget(:final reason):
        return _SkippedClassPrimaryConstructor(reason);
      case _NoPrimaryConstructorTarget():
        return const _NoOpClassPrimaryConstructor();
    }

    final constructor = primaryTarget.constructor;
    if (declaration.mixinKeyword != null && !_isTrivialMixinClassTarget()) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.mixinClassPrimaryConstructor,
      );
    }
    if (_hasNamedPrimaryConstructorConflict(constructor)) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.primaryConstructorConflict,
      );
    }

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

    if (constructor.parameters.parameters.isEmpty &&
        !_hasNamedConstructorSuffix(constructor) &&
        constructor.constKeyword == null &&
        declaration.body.members.length != 1 &&
        !realizationPlan.primaryBodyRequired) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.emptyNonConstConstructorWithMembers,
      );
    }
    if (skipSuperConstructorInitializers &&
        realizationPlan.hasRetainedSuperConstructorInitializer) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.superConstructorInitializer,
      );
    }

    return _MigratedClassPrimaryConstructor(
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

  bool _isTrivialMixinClassTarget() {
    final constructor = declaration.body.members
        .whereType<ConstructorDeclaration>()
        .where(
          (constructor) =>
              constructor.factoryKeyword == null &&
              !_isRedirectingConstructor(constructor),
        )
        .single;
    return constructor.parameters.parameters.isEmpty &&
        constructor.initializers.isEmpty &&
        constructor.body is EmptyFunctionBody;
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
            !_hasNamedConstructorSuffix(constructor) &&
            constructor.constKeyword == null &&
            !primaryBodyRequired
        ? null
        : applySourceEditsInRange(source, parametersRange, parameterEdits);
    final edits = <SourceEdit>[
      if (constructor.constKeyword != null)
        SourceEdit.insert(declaration.classKeyword.end, ' const'),
      if (primaryParameters != null)
        SourceEdit.insert(
          declaration.namePart.end,
          '${_primaryConstructorSuffix(constructor)}$primaryParameters',
        ),
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
      emptyBodyRewrite: bodyRewritePlan.emptyBodyRewrite,
      emptyBodySkipReason: bodyRewritePlan.emptyBodySkipReason,
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

sealed class _PrimaryConstructorTargetDecision {
  const _PrimaryConstructorTargetDecision();
}

final class _PlannedPrimaryConstructorTarget
    extends _PrimaryConstructorTargetDecision {
  const _PlannedPrimaryConstructorTarget(this.target);

  final _PrimaryConstructorTarget target;
}

final class _SkippedPrimaryConstructorTarget
    extends _PrimaryConstructorTargetDecision {
  const _SkippedPrimaryConstructorTarget(this.reason);

  final DeclarationSkipReason reason;
}

final class _NoPrimaryConstructorTarget
    extends _PrimaryConstructorTargetDecision {
  const _NoPrimaryConstructorTarget();
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

bool _isRedirectingConstructor(ConstructorDeclaration constructor) {
  return constructor.redirectedConstructor != null ||
      constructor.initializers.any(
        (initializer) => initializer is RedirectingConstructorInvocation,
      );
}

String _primaryConstructorSuffix(ConstructorDeclaration constructor) {
  final period = constructor.period;
  final name = constructor.name;
  if (period == null || name == null) {
    return '';
  }
  return '.${name.lexeme}';
}

bool _hasNamedConstructorSuffix(ConstructorDeclaration constructor) {
  return constructor.period != null && constructor.name != null;
}

String? _namedPrimaryConstructorBasename(ConstructorDeclaration constructor) {
  final name = constructor.name?.lexeme;
  if (name == null || name == 'new') {
    return null;
  }
  return name;
}
