import 'dart:convert';

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
    this.transformCounts = const {},
    this.skipReasonCounts = const {},
  });

  final String root;
  final String mode;
  final bool dryRun;
  final List<Object?> changedFiles;
  final List<Object?> migratedDeclarations;
  final List<Object?> skippedDeclarations;
  final List<Object?> skippedFiles;
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
      'transformCounts': transformCounts,
      'skipReasonCounts': skipReasonCounts,
    };
  }

  String toJsonString() => jsonEncode(toJson());
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
