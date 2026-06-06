part of '../migration.dart';

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
    final initializationDecision = _ConstructorInitializationPlanner(
      source: source,
      declaration: declaration,
      constructor: constructor,
    ).decide();
    final _ConstructorInitializationPlan initializationPlan;
    switch (initializationDecision) {
      case _PlannedConstructorInitialization(:final plan):
        initializationPlan = plan;
      case _SkippedConstructorInitialization(:final reason):
        return _SkippedClassPrimaryConstructor(reason);
    }
    final privateFieldInitializersByName =
        initializationPlan.privateFieldInitializersByName;

    if (generativeConstructors.any(
      (constructor) =>
          constructor.externalKeyword == null &&
          constructor != unnamedConstructors.single &&
          !_isUnnamedConstructor(constructor),
    )) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.namedConstructor,
      );
    }
    if (constructor.parameters.parameters.isEmpty &&
        constructor.constKeyword == null &&
        declaration.body.members.length != 1) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.emptyNonConstConstructorWithMembers,
      );
    }

    final fieldToParameterDecision =
        _FieldToParameterPlanner(
          source: source,
          declaration: declaration,
          privateFieldInitializersByName: privateFieldInitializersByName,
        ).decideConstructorParameters(
          parameters: constructor.parameters,
          fieldInitializers: initializationPlan.fieldInitializers,
        );
    final List<_ParameterMigrationPlan> parameterPlans;
    switch (fieldToParameterDecision) {
      case _PlannedFieldToParameter(
        parameterPlans: final plannedParameterPlans,
      ):
        parameterPlans = plannedParameterPlans;
      case _SkippedFieldToParameter(:final reason):
        return _SkippedClassPrimaryConstructor(reason);
    }

    return _MigratedClassPrimaryConstructor(
      _buildMigrationPlan(
        constructor: constructor,
        initializationPlan: initializationPlan,
        parameterPlans: parameterPlans,
      ),
    );
  }

  _ClassMigrationPlan _buildMigrationPlan({
    required ConstructorDeclaration constructor,
    required _ConstructorInitializationPlan initializationPlan,
    required List<_ParameterMigrationPlan> parameterPlans,
  }) {
    final constructorParameters = constructor.parameters.parameters;
    final parameterEdits = <SourceEdit>[];
    final primaryBodyRequired = initializationPlan.primaryBodyRequired;
    final removableMembers = <ClassMember>{
      if (!primaryBodyRequired) constructor,
    };
    final parametersRange = _rangeFor(constructor.parameters);

    for (final parameterPlan in parameterPlans) {
      parameterEdits.addAll(parameterPlan.edits);
      removableMembers.addAll(parameterPlan.removableFields);
    }

    final primaryParameters =
        constructorParameters.isEmpty && constructor.constKeyword == null
        ? null
        : applySourceEditsInRange(source, parametersRange, parameterEdits);
    final edits = <SourceEdit>[
      if (constructor.constKeyword != null)
        SourceEdit.insert(declaration.classKeyword.end, ' const'),
      if (primaryParameters != null)
        SourceEdit.insert(declaration.namePart.end, primaryParameters),
      for (final fieldInitializer in initializationPlan.fieldInitializers)
        SourceEdit.insert(
          fieldInitializer.variable.end,
          ' = ${_sourceFor(source, fieldInitializer.expression)}',
        ),
    ];

    if (!primaryBodyRequired &&
        declaration.body.members.length == removableMembers.length) {
      edits.add(SourceEdit.replace(_rangeFor(declaration.body), ';'));
    } else {
      for (final member in removableMembers) {
        final range = _memberRemovalRange(source, member);
        edits.add(SourceEdit.delete(range));
      }
      if (primaryBodyRequired) {
        final range = _memberRemovalRange(source, constructor);
        edits.add(
          SourceEdit.replace(range, initializationPlan.primaryBodySource!),
        );
      }
    }

    return _ClassMigrationPlan(
      edits: edits,
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
