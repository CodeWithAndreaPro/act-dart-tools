part of 'primary_constructors.dart';

class _TargetFileDeclarationPlanner {
  const _TargetFileDeclarationPlanner({
    required this.targetFile,
    required this.source,
    required this.parseSource,
  });

  final TargetDartFile targetFile;
  final String source;
  final ParseTargetDartSource parseSource;

  _PlannedFileMigration? plan() {
    final parseResult = parseSource(source, path: targetFile.path, input: true);
    final filePlanBuilder = _TargetFileMigrationPlanBuilder(
      targetFile: targetFile,
      source: source,
    );

    for (final declaration in parseResult.unit.declarations) {
      final plan = _planDeclaration(declaration);
      filePlanBuilder.addDeclarationPlan(plan);
    }

    return filePlanBuilder.build();
  }

  _DeclarationMigrationPlan _planDeclaration(
    CompilationUnitMember declaration,
  ) {
    if (declaration is MixinDeclaration) {
      return _planMixinDeclaration(declaration);
    }
    if (declaration is ClassDeclaration) {
      return _planClassDeclaration(declaration);
    }
    if (declaration is EnumDeclaration) {
      return _planEnumDeclaration(declaration);
    }
    if (declaration is ExtensionTypeDeclaration) {
      return _planExtensionTypeDeclaration(declaration);
    }
    if (declaration is ExtensionDeclaration) {
      return _planExtensionDeclaration(declaration);
    }
    return const _DeclarationMigrationPlan();
  }

  _DeclarationMigrationPlan _planClassDeclaration(
    ClassDeclaration declaration,
  ) {
    final primaryConstructorPlan = _planClassPrimaryConstructor(declaration);
    final emptyBodyPlan = _planStandaloneEmptyBody(
      body: declaration.body,
      declarationKind: _classDeclarationKind(declaration),
      declarationName: declaration.namePart.typeName.lexeme,
      offset: declaration.offset,
    );
    final constructorShorthandPlan = _planConstructorShorthand(
      primaryConstructorPlan,
      declarationKind: 'constructor',
      declarationName: declaration.namePart.typeName.lexeme,
      members: declaration.body.members,
    );
    return _DeclarationMigrationPlan(
      edits: [
        ...primaryConstructorPlan.edits,
        ...constructorShorthandPlan.edits,
        ...emptyBodyPlan.edits,
      ],
      migratedDeclarations: [
        ...primaryConstructorPlan.migratedDeclarations,
        ...constructorShorthandPlan.migratedDeclarations,
        ...emptyBodyPlan.migratedDeclarations,
      ],
      skippedDeclarations: [
        ...primaryConstructorPlan.skippedDeclarations,
        ...constructorShorthandPlan.skippedDeclarations,
        ...emptyBodyPlan.skippedDeclarations,
      ],
    );
  }

  _DeclarationMigrationPlan _planConstructorShorthand(
    _DeclarationMigrationPlan primaryConstructorPlan, {
    required String declarationKind,
    required String declarationName,
    required NodeList<ClassMember> members,
  }) {
    final primaryConstructorWasMigrated = primaryConstructorPlan
        .migratedDeclarations
        .any(
          (migratedDeclaration) =>
              migratedDeclaration.transform == primaryConstructorTransform,
        );
    final primaryConstructorSkips = primaryConstructorPlan.skippedDeclarations
        .where(
          (skippedDeclaration) =>
              skippedDeclaration.transform == primaryConstructorTransform,
        );
    if (primaryConstructorSkips.any(
      (skippedDeclaration) => !_allowsConstructorShorthandAfterPrimarySkip(
        skippedDeclaration.reason,
      ),
    )) {
      return const _DeclarationMigrationPlan();
    }

    final edits = <SourceEdit>[];
    final migratedDeclarations = <MigratedDeclarationReport>[];
    for (final constructor in members.whereType<ConstructorDeclaration>()) {
      if (primaryConstructorWasMigrated &&
          constructor.factoryKeyword == null &&
          !_isRedirectingConstructor(constructor)) {
        continue;
      }

      final rewrite = _constructorShorthandRewrite(constructor);
      if (rewrite == null) {
        continue;
      }
      edits.add(rewrite);
      migratedDeclarations.add(
        MigratedDeclarationReport(
          path: targetFile.relativePath,
          declarationKind: declarationKind,
          declarationName: _constructorReportName(declarationName, constructor),
          transform: constructorShorthandTransform,
          offset: constructor.offset,
        ),
      );
    }

    return _DeclarationMigrationPlan(
      edits: edits,
      migratedDeclarations: migratedDeclarations,
    );
  }

  bool _allowsConstructorShorthandAfterPrimarySkip(String reason) {
    return switch (reason) {
      'multipleConstructors' ||
      'namedConstructor' ||
      'externalConstructor' ||
      'constructorMetadata' ||
      'constructorComment' ||
      'parameterMetadata' => true,
      _ => false,
    };
  }

  SourceEdit? _constructorShorthandRewrite(ConstructorDeclaration constructor) {
    final typeName = constructor.typeName;
    if (constructor.newKeyword != null || typeName == null) {
      return null;
    }

    if (constructor.factoryKeyword != null) {
      return _factoryConstructorShorthandRewrite(constructor, typeName);
    }

    final name = constructor.name;
    if (name?.lexeme == 'new') {
      return SourceEdit.replace(
        SourceRange.fromStartEnd(start: typeName.offset, end: name!.end),
        'new',
      );
    }
    final replacement = name == null ? 'new' : 'new ';
    final range = SourceRange.fromStartEnd(
      start: typeName.offset,
      end: name?.offset ?? typeName.end,
    );
    return SourceEdit.replace(range, replacement);
  }

  SourceEdit? _factoryConstructorShorthandRewrite(
    ConstructorDeclaration constructor,
    SimpleIdentifier typeName,
  ) {
    final name = constructor.name;
    if (name?.lexeme == 'new') {
      return SourceEdit.replace(
        SourceRange.fromStartEnd(
          start: constructor.factoryKeyword!.end,
          end: name!.end,
        ),
        '',
      );
    }
    final range = name == null
        ? SourceRange.fromStartEnd(
            start: constructor.factoryKeyword!.end,
            end: typeName.end,
          )
        : SourceRange.fromStartEnd(start: typeName.offset, end: name.offset);
    return SourceEdit.replace(range, '');
  }

  String _constructorReportName(
    String declarationName,
    ConstructorDeclaration constructor,
  ) {
    final constructorName = constructor.name?.lexeme;
    if (constructorName == null) {
      return declarationName;
    }
    return '$declarationName.$constructorName';
  }

  _DeclarationMigrationPlan _planStandaloneEmptyBody({
    required AstNode body,
    required String declarationKind,
    required String declarationName,
    required int offset,
  }) {
    final emptyBodyPlanner = _EmptyBodyPlanner(source: source, body: body);
    return switch (emptyBodyPlanner.decide()) {
      _MigratedEmptyClassBody(:final rewrite) => _DeclarationMigrationPlan(
        edits: [rewrite.toEdit()],
        migratedDeclarations: [
          _emptyBodyMigratedReport(
            declarationKind: declarationKind,
            declarationName: declarationName,
            offset: offset,
          ),
        ],
      ),
      _SkippedEmptyClassBody(:final reason) => _DeclarationMigrationPlan(
        skippedDeclarations: [
          _emptyBodySkippedReport(
            declarationKind: declarationKind,
            declarationName: declarationName,
            offset: offset,
            reason: reason,
          ),
        ],
      ),
      _NoOpEmptyClassBody() => const _DeclarationMigrationPlan(),
    };
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
          edits: plan.sourceEdits,
          migratedDeclarations: [
            plan.migratedDeclaration,
            if (plan.emptyBodyRewrite != null)
              _emptyBodyMigratedReport(
                declarationKind: _classDeclarationKind(declaration),
                declarationName: declaration.namePart.typeName.lexeme,
                offset: declaration.offset,
              ),
          ],
          skippedDeclarations: [
            if (plan.emptyBodySkipReason case final reason?)
              _emptyBodySkippedReport(
                declarationKind: _classDeclarationKind(declaration),
                declarationName: declaration.namePart.typeName.lexeme,
                offset: declaration.offset,
                reason: reason,
              ),
          ],
        ),
      _SkippedClassPrimaryConstructor(:final reason) =>
        _DeclarationMigrationPlan(
          skippedDeclarations: [
            SkippedDeclarationReport(
              path: targetFile.relativePath,
              declarationKind: _classDeclarationKind(declaration),
              declarationName: declaration.namePart.typeName.lexeme,
              transform: primaryConstructorTransform,
              offset: declaration.offset,
              reason: reason.code,
              message: reason.message,
            ),
          ],
        ),
      _NoOpClassPrimaryConstructor() => const _DeclarationMigrationPlan(),
    };
  }

  _DeclarationMigrationPlan _planEnumDeclaration(EnumDeclaration declaration) {
    final enumPlanner = _EnumPrimaryConstructorPlanner(
      source: source,
      targetFile: targetFile,
      declaration: declaration,
    );
    final primaryConstructorPlan = switch (enumPlanner.decide()) {
      _MigratedEnumPrimaryConstructor(:final plan) => _DeclarationMigrationPlan(
        edits: plan.sourceEdits,
        migratedDeclarations: [plan.migratedDeclaration],
      ),
      _SkippedEnumPrimaryConstructor(:final reason) =>
        _DeclarationMigrationPlan(
          skippedDeclarations: [
            SkippedDeclarationReport(
              path: targetFile.relativePath,
              declarationKind: 'enum',
              declarationName: declaration.namePart.typeName.lexeme,
              transform: primaryConstructorTransform,
              offset: declaration.offset,
              reason: reason.code,
              message: reason.message,
            ),
          ],
        ),
      _NoOpEnumPrimaryConstructor() => const _DeclarationMigrationPlan(),
    };
    final shorthandPlan = _planConstructorShorthand(
      primaryConstructorPlan,
      declarationKind: 'constructor',
      declarationName: declaration.namePart.typeName.lexeme,
      members: declaration.body.members,
    );
    final emptyBodyPlan = _planStandaloneEmptyBody(
      body: declaration.body,
      declarationKind: 'enum',
      declarationName: declaration.namePart.typeName.lexeme,
      offset: declaration.offset,
    );
    return _DeclarationMigrationPlan(
      edits: [
        ...primaryConstructorPlan.edits,
        ...shorthandPlan.edits,
        ...emptyBodyPlan.edits,
      ],
      migratedDeclarations: [
        ...primaryConstructorPlan.migratedDeclarations,
        ...shorthandPlan.migratedDeclarations,
        ...emptyBodyPlan.migratedDeclarations,
      ],
      skippedDeclarations: [
        ...primaryConstructorPlan.skippedDeclarations,
        ...shorthandPlan.skippedDeclarations,
        ...emptyBodyPlan.skippedDeclarations,
      ],
    );
  }

  _DeclarationMigrationPlan _planMixinDeclaration(
    MixinDeclaration declaration,
  ) {
    return _planStandaloneEmptyBody(
      body: declaration.body,
      declarationKind: 'mixin',
      declarationName: declaration.name.lexeme,
      offset: declaration.offset,
    );
  }

  _DeclarationMigrationPlan _planExtensionTypeDeclaration(
    ExtensionTypeDeclaration declaration,
  ) {
    final primaryConstructorPlan = _planExtensionTypePrimaryConstructor(
      declaration,
    );
    if (primaryConstructorPlan.skippedDeclarations.isNotEmpty) {
      return primaryConstructorPlan;
    }

    final shorthandPlan = _planConstructorShorthand(
      primaryConstructorPlan,
      declarationKind: 'constructor',
      declarationName: declaration.namePart.typeName.lexeme,
      members: declaration.body.members,
    );
    final emptyBodyPlan = _planStandaloneEmptyBody(
      body: declaration.body,
      declarationKind: 'extensionType',
      declarationName: declaration.namePart.typeName.lexeme,
      offset: declaration.offset,
    );
    return _DeclarationMigrationPlan(
      edits: [
        ...primaryConstructorPlan.edits,
        ...shorthandPlan.edits,
        ...emptyBodyPlan.edits,
      ],
      migratedDeclarations: [
        ...primaryConstructorPlan.migratedDeclarations,
        ...shorthandPlan.migratedDeclarations,
        ...emptyBodyPlan.migratedDeclarations,
      ],
      skippedDeclarations: [
        ...primaryConstructorPlan.skippedDeclarations,
        ...shorthandPlan.skippedDeclarations,
        ...emptyBodyPlan.skippedDeclarations,
      ],
    );
  }

  _DeclarationMigrationPlan _planExtensionTypePrimaryConstructor(
    ExtensionTypeDeclaration declaration,
  ) {
    final extensionTypePlanner = _ExtensionTypePrimaryConstructorPlanner(
      declaration: declaration,
    );
    return switch (extensionTypePlanner.decide()) {
      _SkippedExtensionTypePrimaryConstructor(:final reason) =>
        _DeclarationMigrationPlan(
          skippedDeclarations: [
            SkippedDeclarationReport(
              path: targetFile.relativePath,
              declarationKind: 'extensionType',
              declarationName: declaration.namePart.typeName.lexeme,
              transform: primaryConstructorTransform,
              offset: declaration.offset,
              reason: reason.code,
              message: reason.message,
            ),
          ],
        ),
      _NoOpExtensionTypePrimaryConstructor() =>
        const _DeclarationMigrationPlan(),
    };
  }

  _DeclarationMigrationPlan _planExtensionDeclaration(
    ExtensionDeclaration declaration,
  ) {
    return _planStandaloneEmptyBody(
      body: declaration.body,
      declarationKind: 'extension',
      declarationName: declaration.name?.lexeme ?? '<unnamed extension>',
      offset: declaration.offset,
    );
  }

  MigratedDeclarationReport _emptyBodyMigratedReport({
    required String declarationKind,
    required String declarationName,
    required int offset,
  }) {
    return MigratedDeclarationReport(
      path: targetFile.relativePath,
      declarationKind: declarationKind,
      declarationName: declarationName,
      transform: emptyClassBodyTransform,
      offset: offset,
    );
  }

  SkippedDeclarationReport _emptyBodySkippedReport({
    required String declarationKind,
    required String declarationName,
    required int offset,
    required DeclarationSkipReason reason,
  }) {
    return SkippedDeclarationReport(
      path: targetFile.relativePath,
      declarationKind: declarationKind,
      declarationName: declarationName,
      transform: emptyClassBodyTransform,
      offset: offset,
      reason: reason.code,
      message: reason.message,
    );
  }
}

String _classDeclarationKind(ClassDeclaration declaration) {
  return declaration.mixinKeyword == null ? 'class' : 'mixinClass';
}

class _TargetFileMigrationPlanBuilder {
  _TargetFileMigrationPlanBuilder({
    required this.targetFile,
    required this.source,
  });

  final TargetDartFile targetFile;
  final String source;
  final _edits = <SourceEdit>[];
  final _migratedDeclarations = <MigratedDeclarationReport>[];
  final _skippedDeclarations = <SkippedDeclarationReport>[];

  void addDeclarationPlan(_DeclarationMigrationPlan plan) {
    _edits.addAll(plan.edits);
    _migratedDeclarations.addAll(plan.migratedDeclarations);
    _skippedDeclarations.addAll(plan.skippedDeclarations);
  }

  _PlannedFileMigration? build() {
    if (_edits.isEmpty && _skippedDeclarations.isEmpty) {
      return null;
    }

    final hasEdits = _edits.isNotEmpty;
    final transformedSource = hasEdits
        ? applySourceEdits(source, _edits)
        : source;
    return _PlannedFileMigration(
      targetFile: targetFile,
      transformedSource: transformedSource,
      reportFacts: _buildReportFacts(hasEdits: hasEdits),
    );
  }

  _FileMigrationReportFacts _buildReportFacts({required bool hasEdits}) {
    final transformCounts = <String, int>{};
    for (final declaration in _migratedDeclarations) {
      transformCounts[declaration.transform] =
          (transformCounts[declaration.transform] ?? 0) + 1;
    }

    final skipReasonCounts = <String, int>{};
    for (final declaration in _skippedDeclarations) {
      skipReasonCounts[declaration.reason] =
          (skipReasonCounts[declaration.reason] ?? 0) + 1;
    }

    return _FileMigrationReportFacts(
      changedFile: hasEdits ? targetFile.relativePath : null,
      migratedDeclarations: _migratedDeclarations,
      skippedDeclarations: _skippedDeclarations,
      transformCounts: transformCounts,
      skipReasonCounts: skipReasonCounts,
    );
  }
}
