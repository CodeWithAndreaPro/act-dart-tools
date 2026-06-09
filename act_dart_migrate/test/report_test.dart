import 'package:act_dart_migrate/src/core/discovery.dart';
import 'package:act_dart_migrate/src/core/report_contract.dart';
import 'package:act_dart_migrate/src/migrations/primary_constructors/primary_constructors.dart';
import 'package:act_dart_migrate/src/version.dart';
import 'package:test/test.dart';

void main() {
  group('MigrationReport', () {
    test('combines file, directory, and declaration skip counts in order', () {
      final report = MigrationReport.fromRun(
        root: '/target',
        migrationId: primaryConstructorsMigration,
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
        runResult: MigrationRunResult(
          changedFiles: [],
          migratedDeclarations: [],
          skippedDeclarations: [],
          transformCounts: {},
          skipReasonCounts: {
            DeclarationSkipReason.fieldMetadata.code: 2,
            DeclarationSkipReason.multipleConstructors.code: 1,
          },
        ),
        transformOrder: primaryConstructorTransformOrder,
        skipReasonOrder: primaryConstructorSkipReasonOrder,
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
        migrationId: primaryConstructorsMigration,
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
          skippedDirectories: [
            SkippedDirectory(
              relativePath: 'worktrees/checkout',
              reason: FileSkipReason.nestedRepository,
            ),
            SkippedDirectory(
              relativePath: 'build',
              reason: FileSkipReason.excludedDirectory,
            ),
          ],
        ),
        runResult: MigrationRunResult(
          changedFiles: ['lib/z.dart', 'lib/a.dart'],
          migratedDeclarations: [
            MigratedDeclarationReport(
              path: 'lib/z.dart',
              declarationKind: 'class',
              declarationName: 'Z',
              transform: 'primaryConstructor',
              offset: 20,
            ),
            MigratedDeclarationReport(
              path: 'lib/a.dart',
              declarationKind: 'class',
              declarationName: 'A',
              transform: 'primaryConstructor',
              offset: 10,
            ),
          ],
          skippedDeclarations: [
            SkippedDeclarationReport(
              path: 'lib/z.dart',
              declarationKind: 'class',
              declarationName: 'ZSkip',
              transform: 'primaryConstructor',
              offset: 30,
              reason: DeclarationSkipReason.namedConstructor.code,
              message: DeclarationSkipReason.namedConstructor.message,
            ),
            SkippedDeclarationReport(
              path: 'lib/a.dart',
              declarationKind: 'class',
              declarationName: 'ASkip',
              transform: 'primaryConstructor',
              offset: 5,
              reason: DeclarationSkipReason.fieldMetadata.code,
              message: DeclarationSkipReason.fieldMetadata.message,
            ),
          ],
          transformCounts: {'primaryConstructor': 2},
          skipReasonCounts: {
            DeclarationSkipReason.namedConstructor.code: 1,
            DeclarationSkipReason.fieldMetadata.code: 1,
          },
        ),
        transformOrder: primaryConstructorTransformOrder,
        skipReasonOrder: primaryConstructorSkipReasonOrder,
      );
      final json = report.toJson();

      expect(report.changedFiles, ['lib/a.dart', 'lib/z.dart']);
      expect(report.skippedFiles, [
        {'path': 'lib/a.g.dart', 'reason': 'generatedFile'},
        {'path': 'lib/z.g.dart', 'reason': 'generatedFile'},
      ]);
      expect(report.skippedDirectories, [
        {'path': 'build', 'reason': 'excludedDirectory'},
        {'path': 'worktrees/checkout', 'reason': 'nestedRepository'},
      ]);
      expect(json['migratedDeclarations'], [
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
      expect(json['skippedDeclarations'], [
        {
          'path': 'lib/a.dart',
          'declarationKind': 'class',
          'declarationName': 'ASkip',
          'transform': 'primaryConstructor',
          'offset': 5,
          'reason': 'fieldMetadata',
          'message': 'Field metadata is not moved to declaring parameters.',
        },
        {
          'path': 'lib/z.dart',
          'declarationKind': 'class',
          'declarationName': 'ZSkip',
          'transform': 'primaryConstructor',
          'offset': 30,
          'reason': 'namedConstructor',
          'message': 'Named generative constructors are not supported.',
        },
      ]);
    });

    test(
      'serializes mixed declaration facts and deterministic transform counts in order',
      () {
        final report = MigrationReport.fromRun(
          root: '/target',
          migrationId: primaryConstructorsMigration,
          dryRun: true,
          discovery: const TargetPackageFiles(
            dartFiles: [],
            skippedFiles: [],
            skippedDirectories: [],
          ),
          runResult: MigrationRunResult(
            changedFiles: [],
            migratedDeclarations: [
              MigratedDeclarationReport(
                path: 'lib/source.dart',
                declarationKind: 'class',
                declarationName: 'Body',
                transform: emptyClassBodyTransform,
                offset: 10,
              ),
              MigratedDeclarationReport(
                path: 'lib/source.dart',
                declarationKind: 'class',
                declarationName: 'Primary',
                transform: primaryConstructorTransform,
                offset: 10,
              ),
              MigratedDeclarationReport(
                path: 'lib/source.dart',
                declarationKind: 'constructor',
                declarationName: 'Primary.named',
                transform: constructorShorthandTransform,
                offset: 10,
              ),
            ],
            skippedDeclarations: [
              SkippedDeclarationReport(
                path: 'lib/source.dart',
                declarationKind: 'class',
                declarationName: 'SkippedBody',
                transform: emptyClassBodyTransform,
                offset: 20,
                reason: DeclarationSkipReason.fieldComment.code,
                message: DeclarationSkipReason.fieldComment.message,
              ),
              SkippedDeclarationReport(
                path: 'lib/source.dart',
                declarationKind: 'class',
                declarationName: 'SkippedPrimary',
                transform: primaryConstructorTransform,
                offset: 20,
                reason: DeclarationSkipReason.fieldMetadata.code,
                message: DeclarationSkipReason.fieldMetadata.message,
              ),
              SkippedDeclarationReport(
                path: 'lib/source.dart',
                declarationKind: 'constructor',
                declarationName: 'SkippedPrimary.named',
                transform: constructorShorthandTransform,
                offset: 20,
                reason: DeclarationSkipReason.constructorMetadata.code,
                message: DeclarationSkipReason.constructorMetadata.message,
              ),
            ],
            transformCounts: {
              emptyClassBodyTransform: 1,
              constructorShorthandTransform: 1,
              primaryConstructorTransform: 1,
            },
            skipReasonCounts: {
              DeclarationSkipReason.fieldComment.code: 1,
              DeclarationSkipReason.fieldMetadata.code: 1,
              DeclarationSkipReason.constructorMetadata.code: 1,
            },
          ),
          transformOrder: primaryConstructorTransformOrder,
          skipReasonOrder: primaryConstructorSkipReasonOrder,
        );

        final json = report.toJson();

        expect(json['migratedDeclarations'], [
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'Primary',
            'transform': primaryConstructorTransform,
            'offset': 10,
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'constructor',
            'declarationName': 'Primary.named',
            'transform': constructorShorthandTransform,
            'offset': 10,
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'Body',
            'transform': emptyClassBodyTransform,
            'offset': 10,
          },
        ]);
        expect(json['skippedDeclarations'], [
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'SkippedPrimary',
            'transform': primaryConstructorTransform,
            'offset': 20,
            'reason': 'fieldMetadata',
            'message': 'Field metadata is not moved to declaring parameters.',
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'constructor',
            'declarationName': 'SkippedPrimary.named',
            'transform': constructorShorthandTransform,
            'offset': 20,
            'reason': 'constructorMetadata',
            'message':
                'Constructor metadata is not moved to primary constructors.',
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'SkippedBody',
            'transform': emptyClassBodyTransform,
            'offset': 20,
            'reason': 'fieldComment',
            'message':
                'Ambiguous field comments are not moved to declaring parameters.',
          },
        ]);
        expect(json['transformCounts'], {
          primaryConstructorTransform: 1,
          constructorShorthandTransform: 1,
          emptyClassBodyTransform: 1,
        });
        expect(json['skipReasonCounts'], {
          'constructorMetadata': 1,
          'fieldMetadata': 1,
          'fieldComment': 1,
        });
      },
    );

    test('omits absent and zero transform counts', () {
      final report = MigrationReport.fromRun(
        root: '/target',
        migrationId: primaryConstructorsMigration,
        dryRun: true,
        discovery: const TargetPackageFiles(
          dartFiles: [],
          skippedFiles: [],
          skippedDirectories: [],
        ),
        runResult: const MigrationRunResult(
          changedFiles: [],
          migratedDeclarations: [],
          skippedDeclarations: [],
          transformCounts: {
            primaryConstructorTransform: 1,
            constructorShorthandTransform: 0,
          },
          skipReasonCounts: {},
        ),
        transformOrder: primaryConstructorTransformOrder,
        skipReasonOrder: primaryConstructorSkipReasonOrder,
      );

      expect(report.toJson()['transformCounts'], {
        primaryConstructorTransform: 1,
      });
    });

    test('text output summarizes run facts and include-skipped details', () {
      final report = MigrationReport(
        root: '/target',
        migration: primaryConstructorsMigration,
        dryRun: true,
        changedFiles: ['lib/model.dart'],
        migratedDeclarations: [
          MigratedDeclarationReport(
            path: 'lib/model.dart',
            declarationKind: 'class',
            declarationName: 'Model',
            transform: 'primaryConstructor',
            offset: 0,
          ),
        ],
        skippedDeclarations: [
          SkippedDeclarationReport(
            path: 'lib/skip.dart',
            declarationKind: 'class',
            declarationName: 'Skip',
            transform: 'primaryConstructor',
            offset: 0,
            reason: DeclarationSkipReason.fieldMetadata.code,
            message: DeclarationSkipReason.fieldMetadata.message,
          ),
        ],
        skippedFiles: [
          {'path': 'lib/model.g.dart', 'reason': 'generatedFile'},
        ],
        skippedDirectories: [
          {'path': 'build', 'reason': 'excludedDirectory'},
        ],
      );

      final output = report.toTextString(includeSkipped: true);

      expect(output, contains('ACT Dart Migrate: primary-constructors'));
      expect(output, contains('Tool version: $packageVersion'));
      expect(output, contains('Root: /target'));
      expect(output.split('\n').take(5), [
        'ACT Dart Migrate: primary-constructors',
        'Tool version: $packageVersion',
        'Root: /target',
        'Dry run: true',
        'Formatted: false',
      ]);
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
        CliErrorReport(
          code: 'invalidRoot',
          message: 'bad root',
          migration: primaryConstructorsMigration,
        ),
        CliErrorReport(code: 'parseFailure', message: 'bad input'),
        CliErrorReport(code: 'validationFailure', message: 'bad output'),
        CliErrorReport(code: 'internalError', message: 'bad internal state'),
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
          'migration': primaryConstructorsMigration,
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
        {
          'ok': false,
          'schemaVersion': schemaVersion,
          'toolVersion': packageVersion,
          'error': {'code': 'internalError', 'message': 'bad internal state'},
        },
      ]);
    });
  });
}
