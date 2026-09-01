import 'dart:convert';
import 'dart:io';

import 'package:act_dart_migrate/act_dart_migrate.dart';
import 'package:act_dart_migrate/src/core/command_discovery.dart';
import 'package:act_dart_migrate/src/core/discovery.dart';
import 'package:act_dart_migrate/src/core/exit_codes.dart';
import 'package:act_dart_migrate/src/core/report_contract.dart';
import 'package:act_dart_migrate/src/core/target_package_run.dart';
import 'package:act_dart_migrate/src/migrations/primary_constructors/primary_constructors.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('version', () {
    test('root --version prints package version', () async {
      final result = await runCli(['--version']);

      expect(result.exitCode, exitSuccess);
      expect(result.stdout.trim(), packageVersion);
      expect(result.stderr, isEmpty);
    });

    test('package version constant matches pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final versionMatch = RegExp(
        r'^version:\s*(\S+)$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(versionMatch, isNotNull);
      expect(versionMatch!.group(1), packageVersion);
    });
  });

  group('help', () {
    test('root with no arguments prints usage text to stdout', () async {
      final result = await runCli([]);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final output = result.stdout as String;
      expect(
        output,
        contains('ACT Dart Migrate runs Dart migration subcommands.'),
      );
      expect(output, contains('Usage:'));
      expect(output, contains('--version'));
      expect(output, contains('list --json'));
      expect(output, contains('Migration Subcommands:'));
      expect(output, contains('primary-constructors'));
      expect(
        output,
        contains('primary-constructors <target-package> [options]'),
      );
      expect(output, contains('Use . for the current directory'));
      expect(output.split('\n').where(_isOptionLine), [
        '  --dry-run           Preview the migration without writing files.',
        '  --json              Emit a machine-readable JSON report.',
        '  --include-skipped   Include skipped declarations in text output.',
      ]);
      expect(output, contains('--dry-run'));
      expect(output, contains('--json'));
      expect(output, contains('--include-skipped'));
      expect(output, isNot(contains('--skip-super-constructor-initializers')));
      expect(output, isNot(contains('dart run act_dart_migrate migrate')));
      expect(output, isNot(contains('migrate <target-package> [options]')));
      expect(output, isNot(contains('--help')));
      expect(output.trimLeft(), isNot(startsWith('{')));
    });

    test('root --help is not supported', () async {
      final result = await runCli(['--help']);

      expect(result.exitCode, exitArgumentError);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('Unknown Migration Subcommand "--help".'));
      expect(
        result.stderr,
        contains('Run dart run act_dart_migrate for usage'),
      );
      expect(result.stderr, contains('primary-constructors'));
    });

    test('unknown root command with --json omits migration', () async {
      final result = await runCli(['migrate', '--json']);

      expect(result.exitCode, exitArgumentError);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded.keys, ['ok', 'schemaVersion', 'toolVersion', 'error']);
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], {
        'code': 'argumentError',
        'message':
            'Unknown Migration Subcommand "migrate". Run dart run '
            'act_dart_migrate for usage. Available Migration Subcommands: '
            'primary-constructors.',
      });
    });

    test('primary-constructors --help is not supported', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final exitCode = await runActDartMigrate(
        ['primary-constructors', '--help', '--json'],
        stdout: stdout,
        stderr: stderr,
        runner: TargetPackageRunner(
          migration: const PrimaryConstructorMigration(),
          fileSystem: _ThrowingTargetPackageRunFileSystem(),
        ),
      );

      expect(exitCode, exitArgumentError);
      expect(stderr.toString(), isEmpty);
      final decoded = jsonDecode(stdout.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['migration'], primaryConstructorsMigration);
      expect(decoded['error'], {
        'code': 'argumentError',
        'message': 'Could not find an option named "--help".',
      });
    });
  });

  group('command discovery', () {
    test('list --json serializes supported migrations to stdout only', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final exitCode = await runActDartMigrate(
        ['list', '--json'],
        stdout: stdout,
        stderr: stderr,
        runner: TargetPackageRunner(
          migration: const PrimaryConstructorMigration(),
          fileSystem: _ThrowingTargetPackageRunFileSystem(),
        ),
      );

      expect(exitCode, exitSuccess);
      expect(stderr.toString(), isEmpty);
      expect(stdout.toString().trim().split('\n'), hasLength(1));
      final decoded = jsonDecode(stdout.toString()) as Map<String, Object?>;
      expect(decoded.keys, [
        'ok',
        'schemaVersion',
        'toolVersion',
        'migrations',
      ]);
      expect(decoded, {
        'ok': true,
        'schemaVersion': schemaVersion,
        'toolVersion': packageVersion,
        'migrations': [
          {
            'id': primaryConstructorsMigration,
            'displayName': 'Primary Constructors',
            'status': 'stable',
            'targetPackageMinimumDartSdk': '3.13.0',
            'targetPackageRequiredExperiments': <String>[],
            'supportedCommandSyntax': [
              'dart run act_dart_migrate primary-constructors <target-package> --json',
              'dart run act_dart_migrate primary-constructors <target-package> --dry-run',
              'dart run act_dart_migrate primary-constructors <target-package> --include-skipped',
            ],
            'description':
                'Migrate eligible classes and enhanced enums to Dart primary-constructor syntax, with extension type support for representation validation and safe body transforms.',
          },
        ],
      });
    });

    test('command discovery orders migrations by id', () {
      const alpha = MigrationCommandMetadata(
        id: 'alpha',
        displayName: 'Alpha',
        status: 'experimental',
        targetPackageMinimumDartSdk: '3.12.0',
        targetPackageRequiredExperiments: [],
        supportedCommandSyntax: [],
        description: 'Alpha migration.',
      );
      const beta = MigrationCommandMetadata(
        id: 'beta',
        displayName: 'Beta',
        status: 'stable',
        targetPackageMinimumDartSdk: '3.12.0',
        targetPackageRequiredExperiments: [],
        supportedCommandSyntax: [],
        description: 'Beta migration.',
      );

      final report = CommandDiscoveryReport(migrations: [beta, alpha]);
      final migrations = report.toJson()['migrations'] as List<Object?>;

      expect(
        [
          for (final migration in migrations.cast<Map<String, Object?>>())
            migration['id'],
        ],
        ['alpha', 'beta'],
      );
    });

    test('list without --json is unsupported text discovery', () async {
      final result = await runCli(['list']);

      expect(result.exitCode, exitArgumentError);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('The list command only supports --json.'));
    });

    test('list argument errors are root-level machine-readable JSON', () async {
      final result = await runCli(['list', '--unsupported', '--json']);

      expect(result.exitCode, exitArgumentError);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded.keys, ['ok', 'schemaVersion', 'toolVersion', 'error']);
      expect(decoded['ok'], isFalse);
      expect(decoded, isNot(contains('migration')));
      expect(decoded['error'], {
        'code': 'argumentError',
        'message': 'Could not find an option named "--unsupported".',
      });
    });

    test('list positional errors omit migration', () async {
      final result = await runCli(['list', 'extra', '--json']);

      expect(result.exitCode, exitArgumentError);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded, isNot(contains('migration')));
      expect(decoded['error'], {
        'code': 'argumentError',
        'message': 'The list command does not accept positional arguments.',
      });
    });
  });

  group('primary-constructors no-op report', () {
    test('serializes stable JSON report skeleton', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      final report = MigrationReport(
        root: normalizedPath(root),
        migration: primaryConstructorsMigration,
        dryRun: false,
      );

      expect(report.toJson(), {
        'ok': true,
        'migration': primaryConstructorsMigration,
        'schemaVersion': schemaVersion,
        'toolVersion': packageVersion,
        'root': normalizedPath(root),
        'dryRun': false,
        'formatted': false,
        'changedFiles': [],
        'migratedDeclarations': [],
        'skippedDeclarations': [],
        'skippedFiles': [],
        'skippedDirectories': [],
        'transformCounts': {},
        'skipReasonCounts': {},
      });
    });

    test('json output is stdout-only machine-readable JSON', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded.keys, [
        'ok',
        'migration',
        'schemaVersion',
        'toolVersion',
        'root',
        'dryRun',
        'formatted',
        'changedFiles',
        'migratedDeclarations',
        'skippedDeclarations',
        'skippedFiles',
        'skippedDirectories',
        'transformCounts',
        'skipReasonCounts',
      ]);
      expect(decoded, containsPair('ok', true));
      expect(decoded, containsPair('migration', primaryConstructorsMigration));
      expect(decoded, containsPair('schemaVersion', schemaVersion));
      expect(decoded, containsPair('toolVersion', packageVersion));
      expect(decoded, containsPair('root', normalizedPath(root)));
      expect(decoded, containsPair('dryRun', false));
      expect(decoded, containsPair('formatted', false));
      expect(decoded, containsPair('changedFiles', isEmpty));
      expect(decoded, containsPair('migratedDeclarations', isEmpty));
      expect(decoded, containsPair('skippedDeclarations', isEmpty));
      expect(decoded, containsPair('skippedFiles', isEmpty));
      expect(decoded, containsPair('skippedDirectories', isEmpty));
      expect(decoded, containsPair('transformCounts', isEmpty));
      expect(decoded, containsPair('skipReasonCounts', isEmpty));
    });

    test('json output includes deterministic skipped path reports', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, '.dart_tool/generated/cache.dart', 'void cache() {}');
      writeFile(root, 'lib/model.g.dart', 'void generated() {}');
      writeFile(root, 'lib/source.dart', 'void source() {}');
      writeFile(root, 'packages/nested/pubspec.yaml', 'name: nested_package\n');
      writeFile(root, 'packages/nested/lib/nested.dart', 'void nested() {}');
      writeFile(root, 'repos/nested/pubspec.yaml', 'name: nested_repo\n');
      writeFile(root, 'repos/nested/.git/HEAD', 'ref: refs/heads/main\n');
      writeFile(root, 'repos/nested/lib/nested.dart', 'void nested() {}');
      writeFile(root, 'worktrees/checkout/pubspec.yaml', 'name: checkout\n');
      writeFile(
        root,
        'worktrees/checkout/.git',
        'gitdir: /tmp/checkout/.git\n',
      );
      writeFile(
        root,
        'worktrees/checkout/lib/checkout.dart',
        'void checkout() {}',
      );

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['skippedFiles'], [
        {'path': 'lib/model.g.dart', 'reason': 'generatedFile'},
      ]);
      expect(decoded['skippedDirectories'], [
        {'path': '.dart_tool', 'reason': 'excludedDirectory'},
        {'path': 'packages/nested', 'reason': 'nestedPackage'},
        {'path': 'repos/nested', 'reason': 'nestedRepository'},
        {'path': 'worktrees/checkout', 'reason': 'nestedRepository'},
      ]);
      expect(decoded['skipReasonCounts'], {
        'generatedFile': 1,
        'nestedPackage': 1,
        'excludedDirectory': 1,
        'nestedRepository': 2,
      });
    });

    test('skip-only run succeeds with ok true and unchanged source', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const source = '''
class Skip {
  @deprecated
  final String value;

  Skip(this.value);
}
''';
      writeFile(root, 'lib/skip.dart', source);

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['ok'], isTrue);
      expect(decoded['changedFiles'], isEmpty);
      expect(decoded['migratedDeclarations'], isEmpty);
      expect(decoded['skippedDeclarations'], [
        {
          'path': 'lib/skip.dart',
          'declarationKind': 'class',
          'declarationName': 'Skip',
          'transform': 'primaryConstructor',
          'offset': 0,
          'reason': 'fieldMetadata',
          'message': 'Field metadata is not moved to declaring parameters.',
        },
      ]);
      expect(decoded['skippedFiles'], isEmpty);
      expect(decoded['skippedDirectories'], isEmpty);
      expect(decoded['skipReasonCounts'], {'fieldMetadata': 1});
      expect(readFile(root, 'lib/skip.dart'), source);
    });

    test('skipped directory Dart files are not parsed or validated', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'build/broken.dart', 'class {');
      writeFile(root, 'lib/source.dart', 'void source() {}');

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['skippedFiles'], isEmpty);
      expect(decoded['skippedDirectories'], [
        {'path': 'build', 'reason': 'excludedDirectory'},
      ]);
    });

    test('text output summarizes no-op run', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final exitCode = await runActDartMigrate(
        ['primary-constructors', root.path],
        stdout: stdout,
        stderr: stderr,
      );

      expect(exitCode, exitSuccess);
      expect(stderr.toString(), isEmpty);
      expect(
        stdout.toString(),
        contains('ACT Dart Migrate: primary-constructors'),
      );
      expect(stdout.toString(), contains('Tool version: $packageVersion'));
      expect(stdout.toString(), contains('Root: ${normalizedPath(root)}'));
      expect(stdout.toString().split('\n').take(5), [
        'ACT Dart Migrate: primary-constructors',
        'Tool version: $packageVersion',
        'Root: ${normalizedPath(root)}',
        'Dry run: false',
        'Formatted: false',
      ]);
      expect(stdout.toString(), contains('Dry run: false'));
      expect(stdout.toString(), contains('Formatted: false'));
      expect(stdout.toString(), contains('Changed files: 0'));
      expect(stdout.toString(), contains('Migrated declarations: 0'));
      expect(stdout.toString(), contains('Skipped declarations: 0'));
      expect(stdout.toString(), contains('Skipped files: 0'));
      expect(stdout.toString(), contains('Skipped directories: 0'));
    });

    test(
      'include-skipped text output lists skipped files and directories',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/model.g.dart', 'void generated() {}');
        writeFile(
          root,
          'packages/nested/pubspec.yaml',
          'name: nested_package\n',
        );
        writeFile(root, 'packages/nested/lib/nested.dart', 'void nested() {}');

        final stdout = StringBuffer();
        final stderr = StringBuffer();
        final exitCode = await runActDartMigrate(
          ['primary-constructors', root.path, '--include-skipped'],
          stdout: stdout,
          stderr: stderr,
        );

        expect(exitCode, exitSuccess);
        expect(stderr.toString(), isEmpty);
        final output = stdout.toString();
        expect(output, contains('Skipped files: 1'));
        expect(output, contains('Skipped directories: 1'));
        expect(output, contains('Skipped file details:'));
        expect(output, contains('- lib/model.g.dart (generatedFile)'));
        expect(output, contains('Skipped directory details:'));
        expect(output, contains('- packages/nested (nestedPackage)'));
      },
    );

    test('include-skipped does not change JSON-only stdout', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/model.g.dart', 'void generated() {}');

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
        '--include-skipped',
      ]);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['ok'], isTrue);
      expect(decoded['skippedFiles'], [
        {'path': 'lib/model.g.dart', 'reason': 'generatedFile'},
      ]);
      expect(result.stdout, isNot(contains('Skipped file details:')));
    });
  });

  group('failure reports', () {
    test('invalid argument returns argument-error JSON', () async {
      final result = await runCli([
        'primary-constructors',
        '--unsupported',
        '--json',
      ]);

      expect(result.exitCode, exitArgumentError);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['migration'], primaryConstructorsMigration);
      expect(decoded['schemaVersion'], schemaVersion);
      expect(decoded['toolVersion'], packageVersion);
      expect(decoded['error'], {
        'code': 'argumentError',
        'message': 'Could not find an option named "--unsupported".',
      });
    });

    test('more than one target path returns argument-error JSON', () async {
      final result = await runCli([
        'primary-constructors',
        'one',
        'two',
        '--json',
      ]);

      expect(result.exitCode, exitArgumentError);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['migration'], primaryConstructorsMigration);
      expect(decoded['error'], {
        'code': 'argumentError',
        'message': 'Expected exactly one target package path.',
      });
    });

    test('missing target path returns argument-error JSON', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final exitCode = await runActDartMigrate(
        ['primary-constructors', '--json'],
        stdout: stdout,
        stderr: stderr,
        runner: TargetPackageRunner(
          migration: const PrimaryConstructorMigration(),
          fileSystem: _ThrowingTargetPackageRunFileSystem(),
        ),
      );

      expect(exitCode, exitArgumentError);
      expect(stderr.toString(), isEmpty);
      final decoded = jsonDecode(stdout.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['migration'], primaryConstructorsMigration);
      expect(decoded['error'], {
        'code': 'argumentError',
        'message': 'Expected exactly one target package path.',
      });
    });

    for (final flag in [
      '--diff',
      '--include',
      '--exclude',
      '--skip-super-constructor-initializers',
    ]) {
      test('unsupported option $flag returns argument-error JSON', () async {
        final result = await runCli(['primary-constructors', flag, '--json']);

        expect(result.exitCode, exitArgumentError);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['ok'], isFalse);
        expect(decoded['migration'], primaryConstructorsMigration);
        expect(decoded['error'], {
          'code': 'argumentError',
          'message': 'Could not find an option named "$flag".',
        });
      });
    }

    test('input parse failure returns parse-failure JSON', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/broken.dart', 'class {');

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitParseFailure);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['migration'], primaryConstructorsMigration);
      expect(decoded['schemaVersion'], schemaVersion);
      expect(decoded['toolVersion'], packageVersion);
      expect(decoded['error'], isA<Map<String, Object?>>());
      final error = decoded['error'] as Map<String, Object?>;
      expect(error['code'], 'parseFailure');
      expect(error['message'], contains('Failed to parse'));
    });

    test('validation failure returns validation-failure JSON', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final fileSystem = _MemoryTargetPackageRunFileSystem(
        files: {'lib/user.dart': _fieldFormalClass('User')},
      );
      final runner = TargetPackageRunner(
        migration: PrimaryConstructorMigration(
          parseSource: (source, {required path, required input}) {
            if (!input) {
              throw MigrationFailure(
                'Forced transformed-source validation failure for $path.',
                isInputParseFailure: false,
              );
            }
            return parseTargetDartSource(source, path: path, input: input);
          },
        ),
        fileSystem: fileSystem,
      );

      final exitCode = await runActDartMigrate(
        ['primary-constructors', _memoryRoot, '--json'],
        stdout: stdout,
        stderr: stderr,
        runner: runner,
      );

      expect(exitCode, exitValidationFailure);
      expect(stderr.toString(), isEmpty);
      expect(fileSystem.writes, isEmpty);
      final decoded = jsonDecode(stdout.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['migration'], primaryConstructorsMigration);
      expect(decoded['error'], {
        'code': 'validationFailure',
        'message':
            'Forced transformed-source validation failure for $_memoryRoot/lib/user.dart.',
      });
    });

    test(
      'internal failure returns JSON and human diagnostics on stderr',
      () async {
        final stdout = StringBuffer();
        final stderr = StringBuffer();

        final exitCode = await runActDartMigrate(
          ['primary-constructors', _memoryRoot, '--json'],
          stdout: stdout,
          stderr: stderr,
          runner: TargetPackageRunner(
            migration: const PrimaryConstructorMigration(),
            fileSystem: _ThrowingTargetPackageRunFileSystem(),
          ),
        );

        expect(exitCode, exitInternalError);
        final decoded = jsonDecode(stdout.toString()) as Map<String, Object?>;
        expect(decoded, {
          'ok': false,
          'migration': primaryConstructorsMigration,
          'schemaVersion': schemaVersion,
          'toolVersion': packageVersion,
          'error': {
            'code': 'internalError',
            'message': 'Internal error while running migration.',
          },
        });
        expect(stderr.toString(), contains('Unexpected internal error:'));
        expect(stderr.toString(), contains('forced discovery failure'));
        expect(stdout.toString().trim().split('\n'), hasLength(1));
      },
    );
  });

  group('target root', () {
    test(
      'explicit dot target path targets the current working directory',
      () async {
        final stdout = StringBuffer();
        final stderr = StringBuffer();
        final fileSystem = _MemoryTargetPackageRunFileSystem(
          files: const {},
          requestRoot: '.',
        );

        final exitCode = await runActDartMigrate(
          ['primary-constructors', '.', '--json'],
          stdout: stdout,
          stderr: stderr,
          runner: TargetPackageRunner(
            migration: const PrimaryConstructorMigration(),
            fileSystem: fileSystem,
          ),
        );

        expect(exitCode, exitSuccess);
        expect(stderr.toString(), isEmpty);
        final decoded = jsonDecode(stdout.toString()) as Map<String, Object?>;
        expect(decoded['ok'], isTrue);
        expect(decoded['root'], _memoryRoot);
      },
    );

    test(
      'explicit dot without current-directory pubspec returns invalid-root JSON',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'dart_primary_no_pubspec_',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final stdout = StringBuffer();
        final stderr = StringBuffer();
        final previousCurrentDirectory = Directory.current;

        Directory.current = root;
        try {
          final exitCode = await runActDartMigrate(
            ['primary-constructors', '.', '--json'],
            stdout: stdout,
            stderr: stderr,
          );

          expect(exitCode, exitInvalidRoot);
        } finally {
          Directory.current = previousCurrentDirectory;
        }

        expect(stderr.toString(), isEmpty);
        final decoded = jsonDecode(stdout.toString()) as Map<String, Object?>;
        expect(decoded['ok'], isFalse);
        expect(decoded['migration'], primaryConstructorsMigration);
        expect(decoded['schemaVersion'], schemaVersion);
        expect(decoded['toolVersion'], packageVersion);
        expect(decoded['error'], {
          'code': 'invalidRoot',
          'message':
              'Target package root does not exist or has no pubspec.yaml: .',
        });
      },
    );

    test('non-package root returns invalid-root JSON error', () async {
      final root = await Directory.systemTemp.createTemp(
        'dart_primary_no_pubspec_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitInvalidRoot);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['migration'], primaryConstructorsMigration);
      expect(decoded['error'], {
        'code': 'invalidRoot',
        'message':
            'Target package root does not exist or has no pubspec.yaml: ${root.path}',
      });
    });
  });
}

const _memoryRoot = '/target_package';

bool _isOptionLine(String line) => line.trimLeft().startsWith('--');

String _fieldFormalClass(String name) {
  return '''
class $name {
  final String value;

  $name(this.value);
}
''';
}

class _MemoryTargetPackageRunFileSystem implements TargetPackageRunFileSystem {
  _MemoryTargetPackageRunFileSystem({
    required Map<String, String> files,
    this.requestRoot = _memoryRoot,
  }) : files = Map.of(files);

  final Map<String, String> files;
  final String requestRoot;
  final writes = <String, String>{};

  @override
  String? normalizePackageRoot(String? root) {
    return root == requestRoot ? _memoryRoot : null;
  }

  @override
  TargetPackageFiles discover(String root) {
    return TargetPackageFiles(
      dartFiles: [
        for (final path in files.keys)
          TargetDartFile(relativePath: path, path: '$_memoryRoot/$path'),
      ],
      skippedFiles: const [],
      skippedDirectories: const [],
    );
  }

  @override
  String readDartFile(TargetDartFile file) {
    return files[file.relativePath]!;
  }

  @override
  void writeDartFile(TargetDartFile file, String source) {
    writes[file.relativePath] = source;
    files[file.relativePath] = source;
  }
}

class _ThrowingTargetPackageRunFileSystem
    implements TargetPackageRunFileSystem {
  @override
  String? normalizePackageRoot(String? root) {
    return root == _memoryRoot ? _memoryRoot : null;
  }

  @override
  TargetPackageFiles discover(String root) {
    throw StateError('forced discovery failure');
  }

  @override
  String readDartFile(TargetDartFile file) {
    throw UnimplementedError();
  }

  @override
  void writeDartFile(TargetDartFile file, String source) {
    throw UnimplementedError();
  }
}
