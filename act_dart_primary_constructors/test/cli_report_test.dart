import 'dart:convert';
import 'dart:io';

import 'package:dart_primary_constructors/dart_primary_constructors.dart';
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

  group('migrate no-op report', () {
    test('serializes stable JSON report skeleton', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      final report = MigrationReport(
        root: normalizedPath(root),
        mode: 'safe',
        dryRun: false,
      );

      expect(report.toJson(), {
        'ok': true,
        'schemaVersion': schemaVersion,
        'toolVersion': packageVersion,
        'root': normalizedPath(root),
        'mode': 'safe',
        'dryRun': false,
        'formatted': false,
        'changedFiles': [],
        'migratedDeclarations': [],
        'skippedDeclarations': [],
        'skippedFiles': [],
        'transformCounts': {},
        'skipReasonCounts': {},
      });
    });

    test('json output is stdout-only machine-readable JSON', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded, containsPair('ok', true));
      expect(decoded, containsPair('schemaVersion', schemaVersion));
      expect(decoded, containsPair('toolVersion', packageVersion));
      expect(decoded, containsPair('root', normalizedPath(root)));
      expect(decoded, containsPair('mode', 'safe'));
      expect(decoded, containsPair('dryRun', false));
      expect(decoded, containsPair('formatted', false));
      expect(decoded, containsPair('changedFiles', isEmpty));
      expect(decoded, containsPair('migratedDeclarations', isEmpty));
      expect(decoded, containsPair('skippedDeclarations', isEmpty));
      expect(decoded, containsPair('skippedFiles', isEmpty));
      expect(decoded, containsPair('transformCounts', isEmpty));
      expect(decoded, containsPair('skipReasonCounts', isEmpty));
    });

    test('json output includes deterministic skipped file reports', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, '.dart_tool/generated/cache.dart', 'void cache() {}');
      writeFile(root, 'lib/model.g.dart', 'void generated() {}');
      writeFile(root, 'lib/source.dart', 'void source() {}');
      writeFile(root, 'packages/nested/pubspec.yaml', 'name: nested_package\n');
      writeFile(root, 'packages/nested/lib/nested.dart', 'void nested() {}');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['skippedFiles'], [
        {
          'path': '.dart_tool/generated/cache.dart',
          'reason': 'excludedDirectory',
        },
        {'path': 'lib/model.g.dart', 'reason': 'generatedFile'},
        {'path': 'packages/nested/lib/nested.dart', 'reason': 'nestedPackage'},
      ]);
      expect(decoded['skipReasonCounts'], {
        'generatedFile': 1,
        'nestedPackage': 1,
        'excludedDirectory': 1,
      });
    });

    test('text output summarizes no-op run', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final exitCode = await runDartPrimaryConstructors(
        ['migrate', '--root', root.path],
        stdout: stdout,
        stderr: stderr,
      );

      expect(exitCode, exitSuccess);
      expect(stderr.toString(), isEmpty);
      expect(
        stdout.toString(),
        contains('Dart primary constructors migration'),
      );
      expect(stdout.toString(), contains('Tool version: $packageVersion'));
      expect(stdout.toString(), contains('Root: ${normalizedPath(root)}'));
      expect(stdout.toString(), contains('Mode: safe'));
      expect(stdout.toString(), contains('Changed files: 0'));
      expect(stdout.toString(), contains('Migrated declarations: 0'));
    });
  });

  group('invalid root', () {
    test('missing root returns invalid-root JSON error', () async {
      final result = await runCli(['migrate', '--json']);

      expect(result.exitCode, exitInvalidRoot);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['schemaVersion'], schemaVersion);
      expect(decoded['toolVersion'], packageVersion);
      expect(decoded['error'], {
        'code': 'invalidRoot',
        'message': 'A target package root is required.',
      });
    });

    test('non-package root returns invalid-root JSON error', () async {
      final root = await Directory.systemTemp.createTemp(
        'dart_primary_no_pubspec_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitInvalidRoot);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], {
        'code': 'invalidRoot',
        'message':
            'Target package root does not exist or has no pubspec.yaml: ${root.path}',
      });
    });
  });
}
