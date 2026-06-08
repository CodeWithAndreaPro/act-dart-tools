import 'package:act_dart_primary_constructors/src/discovery.dart';
import 'package:act_dart_primary_constructors/src/exit_codes.dart';
import 'package:act_dart_primary_constructors/src/migration.dart';
import 'package:act_dart_primary_constructors/src/target_package_run.dart';
import 'package:test/test.dart';

void main() {
  group('target package runner', () {
    test('dry run reports changes without writing files', () {
      final source = _fieldFormalClass('User');
      final fileSystem = _MemoryTargetPackageRunFileSystem(
        files: {'lib/user.dart': source},
      );

      final outcome = TargetPackageRunner(
        fileSystem: fileSystem,
      ).run(const TargetPackageRunRequest(root: _root, dryRun: true));

      expect(outcome.exitCode, exitSuccess);
      expect(outcome.error, isNull);
      expect(outcome.report, isNotNull);
      expect(outcome.report!.changedFiles, ['lib/user.dart']);
      expect(fileSystem.writes, isEmpty);
      expect(fileSystem.files['lib/user.dart'], source);
    });

    test('input parse failure aborts before writes', () {
      final fileSystem = _MemoryTargetPackageRunFileSystem(
        files: {'lib/broken.dart': 'class {'},
      );

      final outcome = TargetPackageRunner(
        fileSystem: fileSystem,
      ).run(const TargetPackageRunRequest(root: _root, dryRun: false));

      expect(outcome.exitCode, exitParseFailure);
      expect(outcome.report, isNull);
      expect(outcome.error!.code, 'parseFailure');
      expect(fileSystem.writes, isEmpty);
    });

    test('later input parse failure aborts previously planned writes', () {
      final validSource = _fieldFormalClass('User');
      final fileSystem = _MemoryTargetPackageRunFileSystem(
        files: {'lib/user.dart': validSource, 'lib/broken.dart': 'class {'},
      );

      final outcome = TargetPackageRunner(
        fileSystem: fileSystem,
      ).run(const TargetPackageRunRequest(root: _root, dryRun: false));

      expect(outcome.exitCode, exitParseFailure);
      expect(outcome.report, isNull);
      expect(outcome.error!.code, 'parseFailure');
      expect(fileSystem.writes, isEmpty);
      expect(fileSystem.files['lib/user.dart'], validSource);
    });

    test('transformed-source validation failure aborts before writes', () {
      final fileSystem = _MemoryTargetPackageRunFileSystem(
        files: {'lib/user.dart': _fieldFormalClass('User')},
      );
      final runner = TargetPackageRunner(
        fileSystem: fileSystem,
        parseSource: (source, {required path, required input}) {
          if (!input) {
            throw MigrationFailure(
              'Forced transformed-source validation failure for $path.',
              isInputParseFailure: false,
            );
          }
          return parseTargetDartSource(source, path: path, input: input);
        },
      );

      final outcome = runner.run(
        const TargetPackageRunRequest(root: _root, dryRun: false),
      );

      expect(outcome.exitCode, exitValidationFailure);
      expect(outcome.report, isNull);
      expect(outcome.error!.code, 'validationFailure');
      expect(fileSystem.writes, isEmpty);
    });

    test('builds deterministic reports in process', () {
      final fileSystem = _MemoryTargetPackageRunFileSystem(
        files: {
          'lib/b.dart': _fieldFormalClass('Beta'),
          'lib/a.dart': _fieldFormalClass('Alpha'),
        },
        skippedFiles: const [
          SkippedDartFile(
            relativePath: 'lib/z.g.dart',
            reason: FileSkipReason.generatedFile,
          ),
          SkippedDartFile(
            relativePath: 'lib/c.g.dart',
            reason: FileSkipReason.generatedFile,
          ),
        ],
        skippedDirectories: const [
          SkippedDirectory(
            relativePath: 'packages/z_nested',
            reason: FileSkipReason.nestedPackage,
          ),
          SkippedDirectory(
            relativePath: 'build',
            reason: FileSkipReason.excludedDirectory,
          ),
        ],
      );

      final outcome = TargetPackageRunner(
        fileSystem: fileSystem,
      ).run(const TargetPackageRunRequest(root: _root, dryRun: true));

      final report = outcome.report!;
      expect(outcome.exitCode, exitSuccess);
      expect(report.changedFiles, ['lib/a.dart', 'lib/b.dart']);
      expect(
        [
          for (final declaration in report.migratedDeclarations)
            '${declaration.path}:${declaration.transform}',
        ],
        [
          'lib/a.dart:primaryConstructor',
          'lib/a.dart:emptyClassBody',
          'lib/b.dart:primaryConstructor',
          'lib/b.dart:emptyClassBody',
        ],
      );
      expect(report.skippedFiles, [
        {'path': 'lib/c.g.dart', 'reason': 'generatedFile'},
        {'path': 'lib/z.g.dart', 'reason': 'generatedFile'},
      ]);
      expect(report.skippedDirectories, [
        {'path': 'build', 'reason': 'excludedDirectory'},
        {'path': 'packages/z_nested', 'reason': 'nestedPackage'},
      ]);
      expect(report.skipReasonCounts, {
        'generatedFile': 2,
        'nestedPackage': 1,
        'excludedDirectory': 1,
      });
      expect(fileSystem.writes, isEmpty);
    });
  });
}

const _root = '/target_package';

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
    this.skippedFiles = const [],
    this.skippedDirectories = const [],
  }) : files = Map.of(files);

  final Map<String, String> files;
  final List<SkippedDartFile> skippedFiles;
  final List<SkippedDirectory> skippedDirectories;
  final writes = <String, String>{};

  @override
  String? normalizePackageRoot(String? root) {
    return root == _root ? _root : null;
  }

  @override
  TargetPackageFiles discover(String root) {
    return TargetPackageFiles(
      dartFiles: [
        for (final path in files.keys)
          TargetDartFile(relativePath: path, path: '$_root/$path'),
      ],
      skippedFiles: skippedFiles,
      skippedDirectories: skippedDirectories,
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
