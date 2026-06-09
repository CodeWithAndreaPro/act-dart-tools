import 'dart:io';

import 'package:act_dart_migrate/src/core/discovery.dart';
import 'package:act_dart_migrate/src/core/report_contract.dart';
import 'package:act_dart_migrate/src/migrations/primary_constructors/primary_constructors.dart';
import 'package:test/test.dart';

void main() {
  test('README documents active command identity and usage', () {
    final readme = _readPackageDoc('README.md');

    expect(readme, contains('# $_packageName'));
    _expectAllPresent(readme, [
      'dart run $_packageName',
      'dart run $_packageName --version',
      'dart run $_packageName list --json',
      'dart run $_packageName $primaryConstructorsMigration '
          '<target-package> --json',
      'dart run $_packageName $primaryConstructorsMigration '
          '<target-package> --dry-run',
      'dart run $_packageName $primaryConstructorsMigration '
          '<target-package> --include-skipped',
      'dart run $_packageName $primaryConstructorsMigration '
          '<target-package> --skip-super-constructor-initializers',
    ], 'command examples');
  });

  test('package docs avoid stale command identities', () {
    for (final path in _packageDocPaths) {
      final contents = _readPackageDoc(path);

      expect(
        contents,
        isNot(contains(_oldPackageName)),
        reason: '$path must not document the old package identity.',
      );
      expect(
        contents,
        isNot(contains('dart run $_packageName migrate')),
        reason: '$path must not document the removed command shape.',
      );
      expect(
        contents,
        isNot(contains('migrate <target-package>')),
        reason: '$path must not document the removed command shape.',
      );
    }
  });

  test('report contract document includes public report vocabulary', () {
    final reportContract = _readPackageDoc('doc/report_contract.md');

    _expectAllPresent(reportContract, [
      '"migration": "$primaryConstructorsMigration"',
      '"schemaVersion": $schemaVersion',
      'schema version `$schemaVersion`',
      'Root-level errors omit `migration`',
    ], 'report envelope vocabulary');
    _expectAllPresent(reportContract, [
      primaryConstructorTransform,
      DeclarationSkipReason.fieldMetadata.code,
      FileSkipReason.generatedFile.code,
      FileSkipReason.nestedPackage.code,
      FileSkipReason.nestedRepository.code,
      FileSkipReason.excludedDirectory.code,
    ], 'report item vocabulary');
  });

  test('migration rules document includes public migration vocabulary', () {
    final rules = _readPackageDoc('doc/migration_rules.md');

    _expectAllPresent(rules, [
      primaryConstructorTransform,
      constructorShorthandTransform,
      emptyClassBodyTransform,
    ], 'transform names');
    _expectAllPresent(rules, [
      for (final reason in DeclarationSkipReason.values) reason.code,
    ], 'declaration skip reason codes');
    _expectAllPresent(rules, [
      for (final reason in FileSkipReason.values) reason.code,
    ], 'file and directory skip reason codes');
  });

  test('architecture document keeps CLI and ACT responsibilities separate', () {
    final architecture = _readPackageDoc('doc/architecture.md');

    _expectAllPresent(architecture, [
      'one executable',
      'Migration Subcommands',
      'Shared Internal Core',
      'Migration-Specific Modules',
      'The CLI does not own formatting',
      'target package analysis',
      'target package tests',
      'package setup commands',
      'git operations',
      'The stable surface is command behavior and report vocabulary.',
    ], 'architecture boundary language');
  });
}

String _readPackageDoc(String path) => File(path).readAsStringSync();

const _packageName = 'act_dart_migrate';
const _oldPackageName = 'act_dart_primary_constructors';

const _packageDocPaths = [
  'README.md',
  'doc/architecture.md',
  'doc/migration_rules.md',
  'doc/report_contract.md',
];

void _expectAllPresent(
  String contents,
  Iterable<String> expectedValues,
  String label,
) {
  final missing = [
    for (final value in expectedValues)
      if (!contents.contains(value)) value,
  ];

  expect(missing, isEmpty, reason: 'Missing $label: ${missing.join(', ')}');
}
