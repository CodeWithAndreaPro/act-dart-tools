import 'dart:convert';

import 'discovery.dart';
import '../version.dart';

const schemaVersion = 2;

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
  final Map<String, int> skipReasonCounts;
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
    required this.message,
  });

  final String path;
  final String declarationKind;
  final String declarationName;
  final String transform;
  final int offset;
  final String reason;
  final String message;
}

class MigrationReport {
  const MigrationReport({
    required this.root,
    required this.migration,
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
    required String migrationId,
    required bool dryRun,
    required TargetPackageFiles discovery,
    required MigrationRunResult runResult,
    required List<String> transformOrder,
    required List<String> skipReasonOrder,
  }) {
    return MigrationReport(
      root: root,
      migration: migrationId,
      dryRun: dryRun,
      changedFiles: _sortedStrings(runResult.changedFiles),
      migratedDeclarations: _sortedMigratedDeclarationReports(
        runResult.migratedDeclarations,
        transformOrder,
      ),
      skippedDeclarations: _sortedSkippedDeclarationReports(
        runResult.skippedDeclarations,
        transformOrder,
      ),
      skippedFiles: _skippedDartFileReports(discovery.skippedFiles),
      skippedDirectories: _skippedDirectoryReports(
        discovery.skippedDirectories,
      ),
      transformCounts: _orderedTransformCounts(
        runResult.transformCounts,
        transformOrder,
      ),
      skipReasonCounts: _combinedSkipReasonCounts(
        discovery: discovery,
        runResult: runResult,
        skipReasonOrder: skipReasonOrder,
      ),
    );
  }

  final String root;
  final String migration;
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
      'migration': migration,
      'schemaVersion': schemaVersion,
      'toolVersion': packageVersion,
      'root': root,
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
      ..writeln('ACT Dart Migrate: $migration')
      ..writeln('Tool version: $packageVersion')
      ..writeln('Root: $root')
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
          '(${skippedDeclaration.reason})',
        );
      }
    }

    if (includeSkipped && skipReasonCounts.isNotEmpty) {
      buffer.writeln('Skip reason counts:');
      for (final entry in skipReasonCounts.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
    }

    return buffer.toString();
  }
}

class CliErrorReport {
  const CliErrorReport({
    required this.code,
    required this.message,
    this.migration,
  });

  final String code;
  final String message;
  final String? migration;

  CliErrorReport withMigration(String migration) {
    return CliErrorReport(code: code, message: message, migration: migration);
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'ok': false};
    if (migration case final migration?) {
      json['migration'] = migration;
    }
    json['schemaVersion'] = schemaVersion;
    json['toolVersion'] = packageVersion;
    json['error'] = {'code': code, 'message': message};
    return json;
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
  List<String> transformOrder,
) {
  return [...reports]..sort((a, b) {
    return _compareDeclarationSortValues(
      _migratedDeclarationSortValues(a),
      _migratedDeclarationSortValues(b),
      transformOrder,
    );
  });
}

List<SkippedDeclarationReport> _sortedSkippedDeclarationReports(
  List<SkippedDeclarationReport> reports,
  List<String> transformOrder,
) {
  return [...reports]..sort((a, b) {
    return _compareDeclarationSortValues(
      _skippedDeclarationSortValues(a),
      _skippedDeclarationSortValues(b),
      transformOrder,
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
    'reason': declaration.reason,
    'message': declaration.message,
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
    reason: declaration.reason,
  );
}

int _compareDeclarationSortValues(
  _DeclarationSortValues a,
  _DeclarationSortValues b,
  List<String> transformOrder,
) {
  final pathComparison = a.path.compareTo(b.path);
  if (pathComparison != 0) {
    return pathComparison;
  }

  final offsetComparison = a.offset.compareTo(b.offset);
  if (offsetComparison != 0) {
    return offsetComparison;
  }

  final transformComparison = _compareTransformOrder(
    a.transform,
    b.transform,
    transformOrder,
  );
  if (transformComparison != 0) {
    return transformComparison;
  }

  final nameComparison = a.declarationName.compareTo(b.declarationName);
  if (nameComparison != 0) {
    return nameComparison;
  }

  return a.reason.compareTo(b.reason);
}

int _compareTransformOrder(String a, String b, List<String> transformOrder) {
  final aIndex = transformOrder.indexOf(a);
  final bIndex = transformOrder.indexOf(b);
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

Map<String, int> _orderedTransformCounts(
  Map<String, int> counts,
  List<String> transformOrder,
) {
  final ordered = <String, int>{};
  for (final transform in transformOrder) {
    _addCount(ordered, transform, counts[transform] ?? 0);
  }

  final remainingTransforms =
      counts.keys
          .where((transform) => !transformOrder.contains(transform))
          .toList()
        ..sort();
  for (final transform in remainingTransforms) {
    _addCount(ordered, transform, counts[transform] ?? 0);
  }
  return ordered;
}

Map<String, int> _combinedSkipReasonCounts({
  required TargetPackageFiles discovery,
  required MigrationRunResult runResult,
  required List<String> skipReasonOrder,
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
  for (final reason in skipReasonOrder) {
    _addCount(combined, reason, runResult.skipReasonCounts[reason] ?? 0);
  }
  final remainingReasons =
      runResult.skipReasonCounts.keys
          .where((reason) => !skipReasonOrder.contains(reason))
          .toList()
        ..sort();
  for (final reason in remainingReasons) {
    _addCount(combined, reason, runResult.skipReasonCounts[reason] ?? 0);
  }
  return combined;
}

void _addCount(Map<String, int> counts, String key, int count) {
  if (count == 0) {
    return;
  }
  counts[key] = (counts[key] ?? 0) + count;
}
