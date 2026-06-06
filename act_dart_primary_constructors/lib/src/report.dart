import 'dart:convert';

import 'discovery.dart';
import 'version.dart';

const schemaVersion = 1;
const primaryConstructorTransform = 'primaryConstructor';
const constructorShorthandTransform = 'constructorShorthand';
const emptyClassBodyTransform = 'emptyClassBody';

enum DeclarationSkipReason {
  multipleConstructors(
    'multipleConstructors',
    'Multiple generative constructors are not supported.',
  ),
  namedConstructor(
    'namedConstructor',
    'Named generative constructors are not supported.',
  ),
  externalConstructor(
    'externalConstructor',
    'External constructors are not supported.',
  ),
  redirectingConstructor(
    'redirectingConstructor',
    'Redirecting constructors are not supported.',
  ),
  nonEmptyConstructorBody(
    'nonEmptyConstructorBody',
    'Non-empty constructor bodies are not supported.',
  ),
  fieldInitializingConstructorBody(
    'fieldInitializingConstructorBody',
    'Constructor bodies that initialize instance fields are not supported.',
  ),
  unsupportedConstructorBody(
    'unsupportedConstructorBody',
    'This constructor body shape is not supported.',
  ),
  emptyNonConstConstructorWithMembers(
    'emptyNonConstConstructorWithMembers',
    'Empty non-const constructors without parameters are only supported when '
        'the class body can collapse.',
  ),
  constructorMetadata(
    'constructorMetadata',
    'Constructor metadata is not moved to primary constructors.',
  ),
  constructorComment(
    'constructorComment',
    'Constructor comments are not moved to primary constructors.',
  ),
  parameterMetadata(
    'parameterMetadata',
    'Parameter metadata is not moved to declaring parameters.',
  ),
  fieldMetadata(
    'fieldMetadata',
    'Field metadata is not moved to declaring parameters.',
  ),
  fieldComment(
    'fieldComment',
    'Ambiguous field comments are not moved to declaring parameters.',
  ),
  missingField(
    'missingField',
    'A constructor parameter maps to a missing field.',
  ),
  staticField(
    'staticField',
    'Static fields cannot become declaring parameters.',
  ),
  lateField('lateField', 'Late fields cannot become declaring parameters.'),
  externalField(
    'externalField',
    'External fields cannot become declaring parameters.',
  ),
  initializedField(
    'initializedField',
    'Initialized fields cannot become declaring parameters.',
  ),
  implicitFieldType(
    'implicitFieldType',
    'Fields with implicit types cannot become declaring parameters.',
  ),
  multipleFieldVariables(
    'multipleFieldVariables',
    'Multi-variable field declarations cannot become declaring parameters.',
  ),
  unsupportedFieldModifier(
    'unsupportedFieldModifier',
    'This field modifier is not supported for declaring parameters.',
  ),
  unsupportedParameterShape(
    'unsupportedParameterShape',
    'This constructor parameter shape is not supported.',
  ),
  unsafeInitializerDependency(
    'unsafeInitializerDependency',
    'Initializer field assignments must depend only on constructor parameters.',
  ),
  unsupportedInitializer(
    'unsupportedInitializer',
    'This constructor initializer is not supported.',
  ),
  namedSuperInitializer(
    'namedSuperInitializer',
    'Named super constructor initializers are not supported.',
  );

  const DeclarationSkipReason(this.code, this.message);

  final String code;
  final String message;
}

class MigrationRunResult {
  const MigrationRunResult({
    required this.changedFiles,
    required this.migratedDeclarations,
    required this.skippedDeclarations,
    required this.transformCounts,
    required this.skipReasonCounts,
  });

  final List<String> changedFiles;
  final List<MigratedDeclarationReport> migratedDeclarations;
  final List<SkippedDeclarationReport> skippedDeclarations;
  final Map<String, int> transformCounts;
  final Map<DeclarationSkipReason, int> skipReasonCounts;
}

class MigratedDeclarationReport {
  const MigratedDeclarationReport({
    required this.path,
    required this.declarationKind,
    required this.declarationName,
    required this.transform,
    required this.offset,
  });

  final String path;
  final String declarationKind;
  final String declarationName;
  final String transform;
  final int offset;
}

class SkippedDeclarationReport {
  const SkippedDeclarationReport({
    required this.path,
    required this.declarationKind,
    required this.declarationName,
    required this.transform,
    required this.offset,
    required this.reason,
  });

  final String path;
  final String declarationKind;
  final String declarationName;
  final String transform;
  final int offset;
  final DeclarationSkipReason reason;
}

class MigrationReport {
  const MigrationReport({
    required this.root,
    required this.mode,
    required this.dryRun,
    this.changedFiles = const [],
    this.migratedDeclarations = const [],
    this.skippedDeclarations = const [],
    this.skippedFiles = const [],
    this.skippedDirectories = const [],
    this.transformCounts = const {},
    this.skipReasonCounts = const {},
  });

  factory MigrationReport.fromRun({
    required String root,
    required String mode,
    required bool dryRun,
    required TargetPackageFiles discovery,
    required MigrationRunResult migration,
  }) {
    return MigrationReport(
      root: root,
      mode: mode,
      dryRun: dryRun,
      changedFiles: _sortedStrings(migration.changedFiles),
      migratedDeclarations: _sortedMigratedDeclarationReports(
        migration.migratedDeclarations,
      ),
      skippedDeclarations: _sortedSkippedDeclarationReports(
        migration.skippedDeclarations,
      ),
      skippedFiles: _skippedDartFileReports(discovery.skippedFiles),
      skippedDirectories: _skippedDirectoryReports(
        discovery.skippedDirectories,
      ),
      transformCounts: _orderedTransformCounts(migration.transformCounts),
      skipReasonCounts: _combinedSkipReasonCounts(
        discovery: discovery,
        migration: migration,
      ),
    );
  }

  final String root;
  final String mode;
  final bool dryRun;
  final List<String> changedFiles;
  final List<MigratedDeclarationReport> migratedDeclarations;
  final List<SkippedDeclarationReport> skippedDeclarations;
  final List<Object?> skippedFiles;
  final List<Object?> skippedDirectories;
  final Map<String, int> transformCounts;
  final Map<String, int> skipReasonCounts;

  Map<String, Object?> toJson() {
    return {
      'ok': true,
      'schemaVersion': schemaVersion,
      'toolVersion': packageVersion,
      'root': root,
      'mode': mode,
      'dryRun': dryRun,
      'formatted': false,
      'changedFiles': changedFiles,
      'migratedDeclarations': [
        for (final declaration in migratedDeclarations)
          _migratedDeclarationToJson(declaration),
      ],
      'skippedDeclarations': [
        for (final declaration in skippedDeclarations)
          _skippedDeclarationToJson(declaration),
      ],
      'skippedFiles': skippedFiles,
      'skippedDirectories': skippedDirectories,
      'transformCounts': transformCounts,
      'skipReasonCounts': skipReasonCounts,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  String toTextString({required bool includeSkipped}) {
    final buffer = StringBuffer()
      ..writeln('Dart primary constructors migration')
      ..writeln('Tool version: $packageVersion')
      ..writeln('Root: $root')
      ..writeln('Mode: $mode')
      ..writeln('Dry run: $dryRun')
      ..writeln('Formatted: false')
      ..writeln('Changed files: ${changedFiles.length}')
      ..writeln('Migrated declarations: ${migratedDeclarations.length}')
      ..writeln('Skipped declarations: ${skippedDeclarations.length}')
      ..writeln('Skipped files: ${skippedFiles.length}')
      ..writeln('Skipped directories: ${skippedDirectories.length}');

    if (includeSkipped && skippedFiles.isNotEmpty) {
      buffer.writeln('Skipped file details:');
      for (final skippedFile in skippedFiles) {
        if (skippedFile case {
          'path': final String path,
          'reason': final String reason,
        }) {
          buffer.writeln('- $path ($reason)');
        }
      }
    }

    if (includeSkipped && skippedDirectories.isNotEmpty) {
      buffer.writeln('Skipped directory details:');
      for (final skippedDirectory in skippedDirectories) {
        if (skippedDirectory case {
          'path': final String path,
          'reason': final String reason,
        }) {
          buffer.writeln('- $path ($reason)');
        }
      }
    }

    if (includeSkipped && skippedDeclarations.isNotEmpty) {
      buffer.writeln('Skipped declaration details:');
      for (final skippedDeclaration in skippedDeclarations) {
        buffer.writeln(
          '- ${skippedDeclaration.path} '
          '${skippedDeclaration.declarationName} '
          '(${skippedDeclaration.reason.code})',
        );
      }
    }

    return buffer.toString();
  }
}

class CliErrorReport {
  const CliErrorReport({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, Object?> toJson() {
    return {
      'ok': false,
      'schemaVersion': schemaVersion,
      'toolVersion': packageVersion,
      'error': {'code': code, 'message': message},
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

List<String> _sortedStrings(List<String> values) {
  return [...values]..sort();
}

List<Map<String, Object?>> _skippedDartFileReports(
  List<SkippedDartFile> files,
) {
  return _skippedPathReports(
    files.map((file) => (path: file.relativePath, reason: file.reason)),
  );
}

List<Map<String, Object?>> _skippedDirectoryReports(
  List<SkippedDirectory> directories,
) {
  return _skippedPathReports(
    directories.map(
      (directory) => (path: directory.relativePath, reason: directory.reason),
    ),
  );
}

typedef _SkippedPathFact = ({String path, FileSkipReason reason});

List<Map<String, Object?>> _skippedPathReports(
  Iterable<_SkippedPathFact> facts,
) {
  final sortedFacts = facts.toList()
    ..sort((a, b) {
      final pathComparison = a.path.compareTo(b.path);
      if (pathComparison != 0) {
        return pathComparison;
      }
      return a.reason.code.compareTo(b.reason.code);
    });
  return [
    for (final fact in sortedFacts)
      {'path': fact.path, 'reason': fact.reason.code},
  ];
}

List<MigratedDeclarationReport> _sortedMigratedDeclarationReports(
  List<MigratedDeclarationReport> reports,
) {
  return [...reports]..sort((a, b) {
    return _compareDeclarationSortValues(
      _migratedDeclarationSortValues(a),
      _migratedDeclarationSortValues(b),
    );
  });
}

List<SkippedDeclarationReport> _sortedSkippedDeclarationReports(
  List<SkippedDeclarationReport> reports,
) {
  return [...reports]..sort((a, b) {
    return _compareDeclarationSortValues(
      _skippedDeclarationSortValues(a),
      _skippedDeclarationSortValues(b),
    );
  });
}

Map<String, Object?> _migratedDeclarationToJson(
  MigratedDeclarationReport declaration,
) {
  return {
    'path': declaration.path,
    'declarationKind': declaration.declarationKind,
    'declarationName': declaration.declarationName,
    'transform': declaration.transform,
    'offset': declaration.offset,
  };
}

Map<String, Object?> _skippedDeclarationToJson(
  SkippedDeclarationReport declaration,
) {
  return {
    'path': declaration.path,
    'declarationKind': declaration.declarationKind,
    'declarationName': declaration.declarationName,
    'transform': declaration.transform,
    'offset': declaration.offset,
    'reason': declaration.reason.code,
    'message': declaration.reason.message,
  };
}

typedef _DeclarationSortValues = ({
  String path,
  int offset,
  String transform,
  String declarationName,
  String reason,
});

_DeclarationSortValues _migratedDeclarationSortValues(
  MigratedDeclarationReport declaration,
) {
  return (
    path: declaration.path,
    offset: declaration.offset,
    transform: declaration.transform,
    declarationName: declaration.declarationName,
    reason: '',
  );
}

_DeclarationSortValues _skippedDeclarationSortValues(
  SkippedDeclarationReport declaration,
) {
  return (
    path: declaration.path,
    offset: declaration.offset,
    transform: declaration.transform,
    declarationName: declaration.declarationName,
    reason: declaration.reason.code,
  );
}

int _compareDeclarationSortValues(
  _DeclarationSortValues a,
  _DeclarationSortValues b,
) {
  final pathComparison = a.path.compareTo(b.path);
  if (pathComparison != 0) {
    return pathComparison;
  }

  final offsetComparison = a.offset.compareTo(b.offset);
  if (offsetComparison != 0) {
    return offsetComparison;
  }

  final transformComparison = _compareTransformOrder(a.transform, b.transform);
  if (transformComparison != 0) {
    return transformComparison;
  }

  final nameComparison = a.declarationName.compareTo(b.declarationName);
  if (nameComparison != 0) {
    return nameComparison;
  }

  return a.reason.compareTo(b.reason);
}

int _compareTransformOrder(String a, String b) {
  final aIndex = _knownTransformOrder.indexOf(a);
  final bIndex = _knownTransformOrder.indexOf(b);
  if (aIndex != -1 && bIndex != -1) {
    return aIndex.compareTo(bIndex);
  }
  if (aIndex != -1) {
    return -1;
  }
  if (bIndex != -1) {
    return 1;
  }
  return a.compareTo(b);
}

Map<String, int> _orderedTransformCounts(Map<String, int> counts) {
  final ordered = <String, int>{};
  for (final transform in _knownTransformOrder) {
    _addCount(ordered, transform, counts[transform] ?? 0);
  }

  final remainingTransforms =
      counts.keys
          .where((transform) => !_knownTransformOrder.contains(transform))
          .toList()
        ..sort();
  for (final transform in remainingTransforms) {
    _addCount(ordered, transform, counts[transform] ?? 0);
  }
  return ordered;
}

Map<String, int> _combinedSkipReasonCounts({
  required TargetPackageFiles discovery,
  required MigrationRunResult migration,
}) {
  final fileAndDirectoryCounts = {
    for (final reason in FileSkipReason.values) reason: 0,
  };
  for (final file in discovery.skippedFiles) {
    fileAndDirectoryCounts[file.reason] =
        fileAndDirectoryCounts[file.reason]! + 1;
  }
  for (final directory in discovery.skippedDirectories) {
    fileAndDirectoryCounts[directory.reason] =
        fileAndDirectoryCounts[directory.reason]! + 1;
  }

  final combined = <String, int>{};
  for (final reason in FileSkipReason.values) {
    _addCount(combined, reason.code, fileAndDirectoryCounts[reason]!);
  }
  for (final reason in DeclarationSkipReason.values) {
    _addCount(combined, reason.code, migration.skipReasonCounts[reason] ?? 0);
  }
  return combined;
}

void _addCount(Map<String, int> counts, String key, int count) {
  if (count == 0) {
    return;
  }
  counts[key] = (counts[key] ?? 0) + count;
}

const _knownTransformOrder = [
  primaryConstructorTransform,
  constructorShorthandTransform,
  emptyClassBodyTransform,
];
