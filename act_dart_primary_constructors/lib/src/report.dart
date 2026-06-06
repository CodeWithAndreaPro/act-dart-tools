import 'dart:convert';

import 'discovery.dart';
import 'migration.dart';
import 'version.dart';

const schemaVersion = 1;

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
      migratedDeclarations: _sortedDeclarationReports(
        migration.migratedDeclarations,
      ),
      skippedDeclarations: _sortedDeclarationReports(
        migration.skippedDeclarations,
      ),
      skippedFiles: _sortedPathReports(discovery.skippedFileReports),
      skippedDirectories: _sortedPathReports(discovery.skippedDirectoryReports),
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
  final List<Object?> changedFiles;
  final List<Object?> migratedDeclarations;
  final List<Object?> skippedDeclarations;
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
      'migratedDeclarations': migratedDeclarations,
      'skippedDeclarations': skippedDeclarations,
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
        if (skippedDeclaration case {
          'path': final String path,
          'declarationName': final String declarationName,
          'reason': final String reason,
        }) {
          buffer.writeln('- $path $declarationName ($reason)');
        }
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

List<Map<String, Object?>> _sortedPathReports(
  List<Map<String, Object?>> reports,
) {
  return [...reports]..sort((a, b) {
    final pathComparison = _reportString(
      a,
      'path',
    ).compareTo(_reportString(b, 'path'));
    if (pathComparison != 0) {
      return pathComparison;
    }
    return _reportString(a, 'reason').compareTo(_reportString(b, 'reason'));
  });
}

List<Map<String, Object?>> _sortedDeclarationReports(
  List<Map<String, Object?>> reports,
) {
  return [...reports]..sort((a, b) {
    final pathComparison = _reportString(
      a,
      'path',
    ).compareTo(_reportString(b, 'path'));
    if (pathComparison != 0) {
      return pathComparison;
    }

    final offsetComparison = _reportOffset(a).compareTo(_reportOffset(b));
    if (offsetComparison != 0) {
      return offsetComparison;
    }

    final transformComparison = _reportString(
      a,
      'transform',
    ).compareTo(_reportString(b, 'transform'));
    if (transformComparison != 0) {
      return transformComparison;
    }

    final nameComparison = _reportString(
      a,
      'declarationName',
    ).compareTo(_reportString(b, 'declarationName'));
    if (nameComparison != 0) {
      return nameComparison;
    }

    return _reportString(a, 'reason').compareTo(_reportString(b, 'reason'));
  });
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
    _addCount(
      combined,
      reason.code,
      migration.skipReasonCounts[reason.code] ?? 0,
    );
  }

  final knownDeclarationReasons = {
    for (final reason in DeclarationSkipReason.values) reason.code,
  };
  final remainingReasons =
      migration.skipReasonCounts.keys
          .where((reason) => !knownDeclarationReasons.contains(reason))
          .toList()
        ..sort();
  for (final reason in remainingReasons) {
    _addCount(combined, reason, migration.skipReasonCounts[reason] ?? 0);
  }
  return combined;
}

void _addCount(Map<String, int> counts, String key, int count) {
  if (count == 0) {
    return;
  }
  counts[key] = (counts[key] ?? 0) + count;
}

String _reportString(Map<String, Object?> report, String key) {
  return switch (report[key]) {
    final String value => value,
    _ => '',
  };
}

int _reportOffset(Map<String, Object?> report) {
  return switch (report['offset']) {
    final int value => value,
    _ => -1,
  };
}

const _knownTransformOrder = [primaryConstructorTransform];
