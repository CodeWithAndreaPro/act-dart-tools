import 'dart:convert';
import 'dart:io';

import 'package:dart_primary_constructors/dart_primary_constructors.dart';
import 'package:dart_primary_constructors/src/discovery.dart';
import 'package:test/test.dart';

void main() {
  group('version', () {
    test('root --version prints package version', () async {
      final result = await _runCli(['--version']);

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
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      final report = MigrationReport(
        root: _normalizedPath(root),
        mode: 'safe',
        dryRun: false,
      );

      expect(report.toJson(), {
        'ok': true,
        'schemaVersion': schemaVersion,
        'toolVersion': packageVersion,
        'root': _normalizedPath(root),
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
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded, containsPair('ok', true));
      expect(decoded, containsPair('schemaVersion', schemaVersion));
      expect(decoded, containsPair('toolVersion', packageVersion));
      expect(decoded, containsPair('root', _normalizedPath(root)));
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
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, '.dart_tool/generated/cache.dart', 'void cache() {}');
      _writeFile(root, 'lib/model.g.dart', 'void generated() {}');
      _writeFile(root, 'lib/source.dart', 'void source() {}');
      _writeFile(
        root,
        'packages/nested/pubspec.yaml',
        'name: nested_package\n',
      );
      _writeFile(root, 'packages/nested/lib/nested.dart', 'void nested() {}');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

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
      final root = await _createPackageRoot();
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
      expect(stdout.toString(), contains('Root: ${_normalizedPath(root)}'));
      expect(stdout.toString(), contains('Mode: safe'));
      expect(stdout.toString(), contains('Changed files: 0'));
      expect(stdout.toString(), contains('Migrated declarations: 0'));
    });
  });

  group('target package discovery', () {
    test('includes non-generated Dart files across package areas', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'tool/task.dart', 'void task() {}');
      _writeFile(root, 'lib/src/source.dart', 'void source() {}');
      _writeFile(root, 'test/source_test.dart', 'void main() {}');
      _writeFile(root, 'example/example.dart', 'void example() {}');
      _writeFile(root, 'bin/main.dart', 'void main() {}');

      final files = discoverTargetPackageFiles(root);

      expect(_discoveredPaths(files), [
        'bin/main.dart',
        'example/example.dart',
        'lib/src/source.dart',
        'test/source_test.dart',
        'tool/task.dart',
      ]);
      expect(files.skippedFiles, isEmpty);
    });

    test('excludes generated Dart files conservatively', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/real.dart', 'void real() {}');
      _writeFile(root, 'lib/model.g.dart', 'void generated() {}');
      _writeFile(root, 'lib/app_localizations_en.dart', 'void l10n() {}');
      _writeFile(
        root,
        'lib/marker.dart',
        '// GENERATED CODE - DO NOT MODIFY BY HAND\nvoid marker() {}',
      );

      final files = discoverTargetPackageFiles(root);

      expect(_discoveredPaths(files), ['lib/real.dart']);
      expect(_skippedFileReports(files), [
        {'path': 'lib/app_localizations_en.dart', 'reason': 'generatedFile'},
        {'path': 'lib/marker.dart', 'reason': 'generatedFile'},
        {'path': 'lib/model.g.dart', 'reason': 'generatedFile'},
      ]);
    });

    test('excludes transient and hidden tooling directories', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, '.dart_tool/build/source.dart', 'void dartTool() {}');
      _writeFile(root, '.vscode/snippet.dart', 'void vscode() {}');
      _writeFile(root, 'build/cache.dart', 'void buildCache() {}');
      _writeFile(root, 'coverage/report.dart', 'void coverageReport() {}');
      _writeFile(root, 'lib/source.dart', 'void source() {}');

      final files = discoverTargetPackageFiles(root);

      expect(_discoveredPaths(files), ['lib/source.dart']);
      expect(_skippedFileReports(files), [
        {'path': '.dart_tool/build/source.dart', 'reason': 'excludedDirectory'},
        {'path': '.vscode/snippet.dart', 'reason': 'excludedDirectory'},
        {'path': 'build/cache.dart', 'reason': 'excludedDirectory'},
        {'path': 'coverage/report.dart', 'reason': 'excludedDirectory'},
      ]);
    });

    test('excludes nested packages unless targeted directly', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/root.dart', 'void root() {}');
      _writeFile(
        root,
        'packages/nested/pubspec.yaml',
        'name: nested_package\n',
      );
      _writeFile(root, 'packages/nested/lib/nested.dart', 'void nested() {}');

      final rootFiles = discoverTargetPackageFiles(root);
      final nestedFiles = discoverTargetPackageFiles(
        Directory('${root.path}${Platform.pathSeparator}packages/nested'),
      );

      expect(_discoveredPaths(rootFiles), ['lib/root.dart']);
      expect(_skippedFileReports(rootFiles), [
        {'path': 'packages/nested/lib/nested.dart', 'reason': 'nestedPackage'},
      ]);
      expect(_discoveredPaths(nestedFiles), ['lib/nested.dart']);
      expect(nestedFiles.skippedFiles, isEmpty);
    });

    test('orders discovered and skipped files by relative path', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'test/z_test.dart', 'void z() {}');
      _writeFile(root, 'lib/a.dart', 'void a() {}');
      _writeFile(root, 'lib/z.g.dart', 'void zGenerated() {}');
      _writeFile(root, '.dart_tool/b.dart', 'void b() {}');

      final files = discoverTargetPackageFiles(root);

      expect(_discoveredPaths(files), ['lib/a.dart', 'test/z_test.dart']);
      expect(_skippedFileReports(files), [
        {'path': '.dart_tool/b.dart', 'reason': 'excludedDirectory'},
        {'path': 'lib/z.g.dart', 'reason': 'generatedFile'},
      ]);
    });
  });

  group('invalid root', () {
    test('missing root returns invalid-root JSON error', () async {
      final result = await _runCli(['migrate', '--json']);

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

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

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

Future<Directory> _createPackageRoot() async {
  final root = await Directory.systemTemp.createTemp('dart_primary_package_');
  File('${root.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync(
    '''
name: target_package
environment:
  sdk: ^3.12.0
''',
  );
  return root;
}

void _writeFile(Directory root, String relativePath, String contents) {
  final file = File(
    '${root.path}${Platform.pathSeparator}${_systemPath(relativePath)}',
  );
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

String _systemPath(String relativePath) {
  return relativePath.replaceAll('/', Platform.pathSeparator);
}

Future<ProcessResult> _runCli(List<String> arguments) {
  return Process.run(Platform.resolvedExecutable, [
    'run',
    'dart_primary_constructors',
    ...arguments,
  ]);
}

String _normalizedPath(Directory directory) {
  final path = directory.absolute.uri.normalizePath().toFilePath();
  final separator = Platform.pathSeparator;
  if (path.length > separator.length && path.endsWith(separator)) {
    return path.substring(0, path.length - separator.length);
  }
  return path;
}

List<String> _discoveredPaths(TargetPackageFiles files) {
  return [for (final file in files.dartFiles) file.relativePath];
}

List<Map<String, Object?>> _skippedFileReports(TargetPackageFiles files) {
  return [for (final file in files.skippedFiles) file.toJson()];
}
