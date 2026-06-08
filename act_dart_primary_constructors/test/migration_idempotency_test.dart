import 'dart:convert';
import 'dart:io';

import 'package:act_dart_primary_constructors/act_dart_primary_constructors.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('migration idempotency', () {
    test('simple class primary-constructor migration is idempotent', () async {
      await expectIdempotentMigration(
        inputFiles: const {
          'lib/user.dart': '''
class User {
  final String id;

  User(this.id);
}
''',
        },
        expectedRawSources: const {
          'lib/user.dart': '''
class User(final String id) ;
''',
        },
        expectedFirstChangedFiles: const ['lib/user.dart'],
        expectedFirstMigratedDeclarations: const [
          {
            'path': 'lib/user.dart',
            'declarationKind': 'class',
            'declarationName': 'User',
            'transform': 'primaryConstructor',
            'offset': 0,
          },
          {
            'path': 'lib/user.dart',
            'declarationKind': 'class',
            'declarationName': 'User',
            'transform': 'emptyClassBody',
            'offset': 0,
          },
        ],
        expectedFirstTransformCounts: const {
          'primaryConstructor': 1,
          'emptyClassBody': 1,
        },
      );
    });

    test('retained primary-constructor body output is idempotent', () async {
      await expectIdempotentMigration(
        inputFiles: const {
          'lib/logger.dart': '''
class Logger {
  final String id;

  Logger(this.id) {
    print(id);
  }
}
''',
        },
        expectedRawSources: const {
          'lib/logger.dart': '''
class Logger(final String id) {
  this {
    print(id);
  }
}
''',
        },
        expectedFirstChangedFiles: const ['lib/logger.dart'],
        expectedFirstMigratedDeclarations: const [
          {
            'path': 'lib/logger.dart',
            'declarationKind': 'class',
            'declarationName': 'Logger',
            'transform': 'primaryConstructor',
            'offset': 0,
          },
        ],
        expectedFirstTransformCounts: const {'primaryConstructor': 1},
      );
    });

    test('enhanced enum primary-constructor migration is idempotent', () async {
      await expectIdempotentMigration(
        inputFiles: const {
          'lib/status.dart': '''
enum HttpStatus {
  ok(200),
  notFound(404);

  final int code;

  const HttpStatus(this.code);
}
''',
        },
        expectedRawSources: const {
          'lib/status.dart': '''
enum HttpStatus(final int code) {
  ok(200),
  notFound(404);

}
''',
        },
        expectedFirstChangedFiles: const ['lib/status.dart'],
        expectedFirstMigratedDeclarations: const [
          {
            'path': 'lib/status.dart',
            'declarationKind': 'enum',
            'declarationName': 'HttpStatus',
            'transform': 'primaryConstructor',
            'offset': 0,
          },
        ],
        expectedFirstTransformCounts: const {'primaryConstructor': 1},
      );
    });

    test('constructor shorthand output is idempotent', () async {
      const originalSource = '''
class ShorthandOnly {
  ShorthandOnly.named();
}
''';

      await expectIdempotentMigration(
        inputFiles: const {'lib/shorthand.dart': originalSource},
        expectedRawSources: const {
          'lib/shorthand.dart': '''
class ShorthandOnly {
  new named();
}
''',
        },
        expectedFirstChangedFiles: const ['lib/shorthand.dart'],
        expectedFirstMigratedDeclarations: [
          {
            'path': 'lib/shorthand.dart',
            'declarationKind': 'constructor',
            'declarationName': 'ShorthandOnly.named',
            'transform': 'constructorShorthand',
            'offset': originalSource.indexOf('ShorthandOnly.named'),
          },
        ],
        expectedFirstTransformCounts: const {'constructorShorthand': 1},
      );
    });

    test('standalone empty class-body collapse is idempotent', () async {
      await expectIdempotentMigration(
        inputFiles: const {
          'lib/empty.dart': '''
class Empty {}
''',
        },
        expectedRawSources: const {
          'lib/empty.dart': '''
class Empty ;
''',
        },
        expectedFirstChangedFiles: const ['lib/empty.dart'],
        expectedFirstMigratedDeclarations: const [
          {
            'path': 'lib/empty.dart',
            'declarationKind': 'class',
            'declarationName': 'Empty',
            'transform': 'emptyClassBody',
            'offset': 0,
          },
        ],
        expectedFirstTransformCounts: const {'emptyClassBody': 1},
      );
    });

    test('already-collapsed semicolon class bodies are no-ops', () async {
      const source = '''
class AlreadyEmpty;

sealed class Result;
''';

      await expectIdempotentMigration(
        inputFiles: const {'lib/already_empty.dart': source},
        expectedRawSources: const {'lib/already_empty.dart': source},
        expectedFirstChangedFiles: const [],
        expectedFirstMigratedDeclarations: const [],
        expectedFirstTransformCounts: const {},
      );
    });

    test(
      'already-migrated primary-constructor semicolon classes are no-ops',
      () async {
        const source = '''
sealed class Result;

class Success({final String? path}) extends Result;

class Error(final String message) extends Result;
''';

        await expectIdempotentMigration(
          inputFiles: const {'lib/result.dart': source},
          expectedRawSources: const {'lib/result.dart': source},
          expectedFirstChangedFiles: const [],
          expectedFirstMigratedDeclarations: const [],
          expectedFirstTransformCounts: const {},
        );
      },
    );

    test(
      'mixed package migration and no-op declarations are idempotent',
      () async {
        const userSource = '''
class User {
  final String id;

  User(this.id);
}
''';
        const resultSource = '''
sealed class Result;

class Success({final String? path}) extends Result;
''';

        await expectIdempotentMigration(
          inputFiles: const {
            'lib/result.dart': resultSource,
            'lib/user.dart': userSource,
          },
          expectedRawSources: const {
            'lib/result.dart': resultSource,
            'lib/user.dart': '''
class User(final String id) ;
''',
          },
          expectedFirstChangedFiles: const ['lib/user.dart'],
          expectedFirstMigratedDeclarations: const [
            {
              'path': 'lib/user.dart',
              'declarationKind': 'class',
              'declarationName': 'User',
              'transform': 'primaryConstructor',
              'offset': 0,
            },
            {
              'path': 'lib/user.dart',
              'declarationKind': 'class',
              'declarationName': 'User',
              'transform': 'emptyClassBody',
              'offset': 0,
            },
          ],
          expectedFirstTransformCounts: const {
            'primaryConstructor': 1,
            'emptyClassBody': 1,
          },
        );
      },
    );
  });
}

Future<void> expectIdempotentMigration({
  required Map<String, String> inputFiles,
  required Map<String, String> expectedRawSources,
  required List<String> expectedFirstChangedFiles,
  required List<Map<String, Object?>> expectedFirstMigratedDeclarations,
  required Map<String, Object?> expectedFirstTransformCounts,
}) async {
  final root = await createPackageRoot();
  addTearDown(() => root.deleteSync(recursive: true));

  for (final entry in inputFiles.entries) {
    writeFile(root, entry.key, entry.value);
  }

  final firstResult = await runCli(['migrate', root.path, '--json']);
  final firstReport = expectMigrationResult(firstResult);
  expect(firstReport['changedFiles'], expectedFirstChangedFiles);
  expect(
    firstReport['migratedDeclarations'],
    expectedFirstMigratedDeclarations,
  );
  expect(firstReport['skippedDeclarations'], isEmpty);
  expect(firstReport['skippedFiles'], isEmpty);
  expect(firstReport['skippedDirectories'], isEmpty);
  expect(firstReport['transformCounts'], expectedFirstTransformCounts);
  expect(firstReport['skipReasonCounts'], isEmpty);

  final filesAfterFirstRun = <String, String>{};
  for (final entry in expectedRawSources.entries) {
    final source = readFile(root, entry.key);
    expect(source, entry.value, reason: entry.key);
    filesAfterFirstRun[entry.key] = source;
  }

  final secondResult = await runCli(['migrate', root.path, '--json']);
  final secondReport = expectMigrationResult(secondResult);
  expect(secondReport['changedFiles'], isEmpty);
  expect(secondReport['migratedDeclarations'], isEmpty);
  expect(secondReport['skippedDeclarations'], isEmpty);
  expect(secondReport['skippedFiles'], isEmpty);
  expect(secondReport['skippedDirectories'], isEmpty);
  expect(secondReport['transformCounts'], isEmpty);
  expect(secondReport['skipReasonCounts'], isEmpty);

  for (final entry in filesAfterFirstRun.entries) {
    expect(readFile(root, entry.key), entry.value, reason: entry.key);
  }
}

Map<String, Object?> expectMigrationResult(ProcessResult result) {
  expect(result.exitCode, exitSuccess);
  expect(result.stderr, isEmpty);
  final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
  expect(decoded['ok'], isTrue);
  return decoded;
}
