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
    final bodySkipReason = _constructorBodySkipReason(
      declaration: declaration,
      constructor: constructor,
    );
    if (bodySkipReason != null) {
      return _SkippedClassPrimaryConstructor(bodySkipReason);
    }
    final initializerClassification = _classifyConstructorInitializers(
      source: source,
      declaration: declaration,
      constructor: constructor,
      parameterNames: _constructorParameterNames(constructor),
    );
    if (initializerClassification.skipReason case final skipReason?) {
      return _SkippedClassPrimaryConstructor(skipReason);
    }
    final initializerPlan = initializerClassification.plan!;
    final privateFieldInitializersByName =
        initializerPlan.privateFieldInitializersByName;

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

    final parameterPlans = <_ParameterMigrationPlan>[];
    final parametersOffset = constructor.parameters.offset;
    final fieldToParameterPlanner = _FieldToParameterPlanner(
      source: source,
      declaration: declaration,
      privateFieldInitializersByName: privateFieldInitializersByName,
      parametersOffset: parametersOffset,
    );
    for (final parameter in constructor.parameters.parameters) {
      final parameterDecision =
          parameter is SuperFormalParameter &&
              _isSimpleSuperFormalParameter(parameter)
          ? const _PlannedConstructorParameter(_ParameterMigrationPlan())
          : fieldToParameterPlanner.decide(parameter);
      switch (parameterDecision) {
        case _PlannedConstructorParameter(:final plan):
          parameterPlans.add(plan);
        case _SkippedConstructorParameter(:final reason):
          return _SkippedClassPrimaryConstructor(reason);
      }
    }

    if (fieldToParameterPlanner.hasUnusedPrivateFieldInitializers) {
      return const _SkippedClassPrimaryConstructor(
        DeclarationSkipReason.unsupportedInitializer,
      );
    }
    for (final fieldInitializer in initializerPlan.fieldInitializers) {
      if (fieldToParameterPlanner.usesField(fieldInitializer.fieldName)) {
        return const _SkippedClassPrimaryConstructor(
          DeclarationSkipReason.unsupportedInitializer,
        );
      }
    }

    return _MigratedClassPrimaryConstructor(
      _buildMigrationPlan(
        constructor: constructor,
        initializerPlan: initializerPlan,
        parameterPlans: parameterPlans,
      ),
    );
  }

  _ClassMigrationPlan _buildMigrationPlan({
    required ConstructorDeclaration constructor,
    required _ConstructorInitializerPlan initializerPlan,
    required List<_ParameterMigrationPlan> parameterPlans,
  }) {
    final constructorParameters = constructor.parameters.parameters;
    final parameterEdits = <SourceEdit>[];
    final retainedInitializers = initializerPlan.retainedInitializers;
    final primaryBodyRequired =
        retainedInitializers.isNotEmpty ||
        constructor.body is BlockFunctionBody;
    final removableMembers = <ClassMember>{
      if (!primaryBodyRequired) constructor,
    };
    final parametersSource = _sourceFor(source, constructor.parameters);

    for (final parameterPlan in parameterPlans) {
      parameterEdits.addAll(parameterPlan.edits);
      removableMembers.addAll(parameterPlan.removableFields);
    }

    final primaryParameters =
        constructorParameters.isEmpty && constructor.constKeyword == null
        ? null
        : applySourceEdits(parametersSource, parameterEdits);
    final edits = <SourceEdit>[
      if (constructor.constKeyword != null)
        SourceEdit(
          offset: declaration.classKeyword.end,
          length: 0,
          replacement: ' const',
        ),
      if (primaryParameters != null)
        SourceEdit(
          offset: declaration.namePart.end,
          length: 0,
          replacement: primaryParameters,
        ),
      for (final fieldInitializer in initializerPlan.fieldInitializers)
        SourceEdit(
          offset: fieldInitializer.variable.end,
          length: 0,
          replacement: ' = ${_sourceFor(source, fieldInitializer.expression)}',
        ),
    ];

    if (!primaryBodyRequired &&
        declaration.body.members.length == removableMembers.length) {
      edits.add(
        SourceEdit(
          offset: declaration.body.offset,
          length: declaration.body.length,
          replacement: ';',
        ),
      );
    } else {
      for (final member in removableMembers) {
        final range = _memberRemovalRange(source, member);
        edits.add(
          SourceEdit(
            offset: range.offset,
            length: range.length,
            replacement: '',
          ),
        );
      }
      if (primaryBodyRequired) {
        final range = _memberRemovalRange(source, constructor);
        edits.add(
          SourceEdit(
            offset: range.offset,
            length: range.length,
            replacement: _primaryConstructorBodySource(
              constructor: constructor,
              retainedInitializers: retainedInitializers,
            ),
          ),
        );
      }
    }

    return _ClassMigrationPlan(
      edits: edits,
      migratedDeclaration: _MigratedDeclaration(
        path: targetFile.relativePath,
        declarationKind: 'class',
        declarationName: declaration.namePart.typeName.lexeme,
        transform: primaryConstructorTransform,
        offset: declaration.offset,
      ),
    );
  }

  String _primaryConstructorBodySource({
    required ConstructorDeclaration constructor,
    required List<ConstructorInitializer> retainedInitializers,
  }) {
    final indent = _lineIndentation(source, constructor.offset);
    final initializerSource = retainedInitializers.isEmpty
        ? ''
        : ' : ${retainedInitializers.map((initializer) => _sourceFor(source, initializer)).join(', ')}';
    final body = constructor.body;
    final bodySource = body is BlockFunctionBody
        ? ' ${_sourceFor(source, body)}'
        : ';';
    return '${indent}this$initializerSource$bodySource\n';
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

sealed class _ConstructorParameterDecision {
  const _ConstructorParameterDecision();
}

final class _PlannedConstructorParameter extends _ConstructorParameterDecision {
  const _PlannedConstructorParameter(this.plan);

  final _ParameterMigrationPlan plan;
}

final class _SkippedConstructorParameter extends _ConstructorParameterDecision {
  const _SkippedConstructorParameter(this.reason);

  final DeclarationSkipReason reason;
}

bool _isUnnamedConstructor(ConstructorDeclaration constructor) {
  return constructor.name == null && constructor.period == null;
}

bool _isSimpleSuperFormalParameter(SuperFormalParameter parameter) {
  return parameter.metadata.isEmpty &&
      parameter.documentationComment == null &&
      parameter.constFinalOrVarKeyword == null &&
      parameter.covariantKeyword == null &&
      parameter.type == null &&
      parameter.functionTypedSuffix == null;
}
