import 'package:act_dart_primary_constructors/act_dart_primary_constructors.dart';
import 'package:act_dart_primary_constructors/src/discovery.dart';
import 'package:act_dart_primary_constructors/src/migration.dart';
import 'package:test/test.dart';

void main() {
  group('MigrationReport', () {
    test('combines file, directory, and declaration skip counts in order', () {
      final report = MigrationReport.fromRun(
        root: '/target',
        mode: 'safe',
        dryRun: true,
        discovery: const TargetPackageFiles(
          dartFiles: [],
          skippedFiles: [
            SkippedDartFile(
              relativePath: 'lib/model.g.dart',
              reason: FileSkipReason.generatedFile,
            ),
          ],
          skippedDirectories: [
            SkippedDirectory(
              relativePath: 'build',
              reason: FileSkipReason.excludedDirectory,
            ),
            SkippedDirectory(
              relativePath: 'packages/nested',
              reason: FileSkipReason.nestedPackage,
            ),
          ],
        ),
        migration: const MigrationRunResult(
          changedFiles: [],
          migratedDeclarations: [],
          skippedDeclarations: [],
          transformCounts: {},
          skipReasonCounts: {'fieldMetadata': 2, 'multipleConstructors': 1},
        ),
      );

      expect(report.skipReasonCounts, {
        'generatedFile': 1,
        'nestedPackage': 1,
        'excludedDirectory': 1,
        'multipleConstructors': 1,
        'fieldMetadata': 2,
      });
      expect(report.skipReasonCounts.keys, [
        'generatedFile',
        'nestedPackage',
        'excludedDirectory',
        'multipleConstructors',
        'fieldMetadata',
      ]);
    });

    test('sorts report arrays deterministically when built from a run', () {
      final report = MigrationReport.fromRun(
        root: '/target',
        mode: 'safe',
        dryRun: false,
        discovery: const TargetPackageFiles(
          dartFiles: [],
          skippedFiles: [
            SkippedDartFile(
              relativePath: 'lib/z.g.dart',
              reason: FileSkipReason.generatedFile,
            ),
            SkippedDartFile(
              relativePath: 'lib/a.g.dart',
              reason: FileSkipReason.generatedFile,
            ),
          ],
          skippedDirectories: [],
        ),
        migration: const MigrationRunResult(
          changedFiles: ['lib/z.dart', 'lib/a.dart'],
          migratedDeclarations: [
            {
              'path': 'lib/z.dart',
              'declarationKind': 'class',
              'declarationName': 'Z',
              'transform': 'primaryConstructor',
              'offset': 20,
            },
            {
              'path': 'lib/a.dart',
              'declarationKind': 'class',
              'declarationName': 'A',
              'transform': 'primaryConstructor',
              'offset': 10,
            },
          ],
          skippedDeclarations: [],
          transformCounts: {'primaryConstructor': 2},
          skipReasonCounts: {},
        ),
      );

      expect(report.changedFiles, ['lib/a.dart', 'lib/z.dart']);
      expect(report.skippedFiles, [
        {'path': 'lib/a.g.dart', 'reason': 'generatedFile'},
        {'path': 'lib/z.g.dart', 'reason': 'generatedFile'},
      ]);
      expect(report.migratedDeclarations, [
        {
          'path': 'lib/a.dart',
          'declarationKind': 'class',
          'declarationName': 'A',
          'transform': 'primaryConstructor',
          'offset': 10,
        },
        {
          'path': 'lib/z.dart',
          'declarationKind': 'class',
          'declarationName': 'Z',
          'transform': 'primaryConstructor',
          'offset': 20,
        },
      ]);
    });

    test('text output summarizes run facts and include-skipped details', () {
      const report = MigrationReport(
        root: '/target',
        mode: 'safe',
        dryRun: true,
        changedFiles: ['lib/model.dart'],
        migratedDeclarations: [
          {
            'path': 'lib/model.dart',
            'declarationKind': 'class',
            'declarationName': 'Model',
            'transform': 'primaryConstructor',
            'offset': 0,
          },
        ],
        skippedDeclarations: [
          {
            'path': 'lib/skip.dart',
            'declarationKind': 'class',
            'declarationName': 'Skip',
            'transform': 'primaryConstructor',
            'offset': 0,
            'reason': 'fieldMetadata',
          },
        ],
        skippedFiles: [
          {'path': 'lib/model.g.dart', 'reason': 'generatedFile'},
        ],
        skippedDirectories: [
          {'path': 'build', 'reason': 'excludedDirectory'},
        ],
      );

      final output = report.toTextString(includeSkipped: true);

      expect(output, contains('Dart primary constructors migration'));
      expect(output, contains('Tool version: $packageVersion'));
      expect(output, contains('Root: /target'));
      expect(output, contains('Mode: safe'));
      expect(output, contains('Dry run: true'));
      expect(output, contains('Formatted: false'));
      expect(output, contains('Changed files: 1'));
      expect(output, contains('Migrated declarations: 1'));
      expect(output, contains('Skipped declarations: 1'));
      expect(output, contains('Skipped files: 1'));
      expect(output, contains('Skipped directories: 1'));
      expect(output, contains('Skipped file details:'));
      expect(output, contains('- lib/model.g.dart (generatedFile)'));
      expect(output, contains('Skipped directory details:'));
      expect(output, contains('- build (excludedDirectory)'));
      expect(output, contains('Skipped declaration details:'));
      expect(output, contains('- lib/skip.dart Skip (fieldMetadata)'));

      final conciseOutput = report.toTextString(includeSkipped: false);
      expect(conciseOutput, isNot(contains('Skipped file details:')));
      expect(conciseOutput, isNot(contains('Skipped directory details:')));
      expect(conciseOutput, isNot(contains('Skipped declaration details:')));
    });
  });

  group('CliErrorReport', () {
    test('serializes stable error JSON shape and codes', () {
      const reports = [
        CliErrorReport(code: 'argumentError', message: 'bad arguments'),
        CliErrorReport(code: 'invalidRoot', message: 'bad root'),
        CliErrorReport(code: 'parseFailure', message: 'bad input'),
        CliErrorReport(code: 'validationFailure', message: 'bad output'),
      ];

      expect(reports.map((report) => report.toJson()).toList(), [
        {
          'ok': false,
          'schemaVersion': schemaVersion,
          'toolVersion': packageVersion,
          'error': {'code': 'argumentError', 'message': 'bad arguments'},
        },
        {
          'ok': false,
          'schemaVersion': schemaVersion,
          'toolVersion': packageVersion,
          'error': {'code': 'invalidRoot', 'message': 'bad root'},
        },
        {
          'ok': false,
          'schemaVersion': schemaVersion,
          'toolVersion': packageVersion,
          'error': {'code': 'parseFailure', 'message': 'bad input'},
        },
        {
          'ok': false,
          'schemaVersion': schemaVersion,
          'toolVersion': packageVersion,
          'error': {'code': 'validationFailure', 'message': 'bad output'},
        },
      ]);
    });
  });
}
