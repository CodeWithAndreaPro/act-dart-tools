import 'dart:convert';

import '../version.dart';
import 'report_contract.dart';

class CommandDiscoveryReport {
  const CommandDiscoveryReport({required this.migrations});

  final List<MigrationCommandMetadata> migrations;

  Map<String, Object?> toJson() {
    return {
      'ok': true,
      'schemaVersion': schemaVersion,
      'toolVersion': packageVersion,
      'migrations': [
        for (final migration in sortedMigrationCommandMetadata(migrations))
          migration.toJson(),
      ],
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

class MigrationCommandMetadata {
  const MigrationCommandMetadata({
    required this.id,
    required this.displayName,
    required this.status,
    required this.targetPackageMinimumDartSdk,
    required this.targetPackageRequiredExperiments,
    required this.supportedCommandSyntax,
    required this.description,
  });

  final String id;
  final String displayName;
  final String status;
  final String targetPackageMinimumDartSdk;
  final List<String> targetPackageRequiredExperiments;
  final List<String> supportedCommandSyntax;
  final String description;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'status': status,
      'targetPackageMinimumDartSdk': targetPackageMinimumDartSdk,
      'targetPackageRequiredExperiments': targetPackageRequiredExperiments,
      'supportedCommandSyntax': supportedCommandSyntax,
      'description': description,
    };
  }
}

List<MigrationCommandMetadata> sortedMigrationCommandMetadata(
  Iterable<MigrationCommandMetadata> migrations,
) {
  return migrations.toList()..sort((a, b) => a.id.compareTo(b.id));
}
