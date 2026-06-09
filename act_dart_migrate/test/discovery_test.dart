import 'dart:io';

import 'package:act_dart_migrate/src/discovery.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('target package discovery', () {
    test('includes non-generated Dart files across package areas', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'tool/task.dart', 'void task() {}');
      writeFile(root, 'lib/src/source.dart', 'void source() {}');
      writeFile(root, 'test/source_test.dart', 'void main() {}');
      writeFile(root, 'example/example.dart', 'void example() {}');
      writeFile(root, 'bin/main.dart', 'void main() {}');

      final files = discoverTargetPackageFiles(root);

      expect(discoveredPaths(files), [
        'bin/main.dart',
        'example/example.dart',
        'lib/src/source.dart',
        'test/source_test.dart',
        'tool/task.dart',
      ]);
      expect(files.skippedFiles, isEmpty);
      expect(files.skippedDirectories, isEmpty);
    });

    test('excludes generated Dart files conservatively', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/real.dart', 'void real() {}');
      writeFile(root, 'lib/model.g.dart', 'void generated() {}');
      writeFile(root, 'lib/app_localizations_en.dart', 'void l10n() {}');
      writeFile(
        root,
        'lib/marker.dart',
        '// GENERATED CODE - DO NOT MODIFY BY HAND\nvoid marker() {}',
      );

      final files = discoverTargetPackageFiles(root);

      expect(discoveredPaths(files), ['lib/real.dart']);
      expect(skippedFileFacts(files), [
        (
          path: 'lib/app_localizations_en.dart',
          reason: FileSkipReason.generatedFile,
        ),
        (path: 'lib/marker.dart', reason: FileSkipReason.generatedFile),
        (path: 'lib/model.g.dart', reason: FileSkipReason.generatedFile),
      ]);
      expect(files.skippedDirectories, isEmpty);
    });

    test('excludes transient and hidden tooling directories', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, '.dart_tool/build/source.dart', 'void dartTool() {}');
      writeFile(root, '.vscode/snippet.dart', 'void vscode() {}');
      writeFile(root, 'build/cache.dart', 'void buildCache() {}');
      writeFile(root, 'coverage/report.dart', 'void coverageReport() {}');
      writeFile(root, 'lib/source.dart', 'void source() {}');

      final files = discoverTargetPackageFiles(root);

      expect(discoveredPaths(files), ['lib/source.dart']);
      expect(files.skippedFiles, isEmpty);
      expect(skippedDirectoryFacts(files), [
        (path: '.dart_tool', reason: FileSkipReason.excludedDirectory),
        (path: '.vscode', reason: FileSkipReason.excludedDirectory),
        (path: 'build', reason: FileSkipReason.excludedDirectory),
        (path: 'coverage', reason: FileSkipReason.excludedDirectory),
      ]);
    });

    test('excludes nested packages unless targeted directly', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/root.dart', 'void root() {}');
      writeFile(root, 'packages/nested/pubspec.yaml', 'name: nested_package\n');
      writeFile(root, 'packages/nested/lib/nested.dart', 'void nested() {}');

      final rootFiles = discoverTargetPackageFiles(root);
      final nestedFiles = discoverTargetPackageFiles(
        Directory('${root.path}${Platform.pathSeparator}packages/nested'),
      );

      expect(discoveredPaths(rootFiles), ['lib/root.dart']);
      expect(rootFiles.skippedFiles, isEmpty);
      expect(skippedDirectoryFacts(rootFiles), [
        (path: 'packages/nested', reason: FileSkipReason.nestedPackage),
      ]);
      expect(discoveredPaths(nestedFiles), ['lib/nested.dart']);
      expect(nestedFiles.skippedFiles, isEmpty);
      expect(nestedFiles.skippedDirectories, isEmpty);
    });

    test('reports nested git repositories before nested packages', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/root.dart', 'void root() {}');
      writeFile(root, 'repos/nested/pubspec.yaml', 'name: nested_package\n');
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

      final files = discoverTargetPackageFiles(root);

      expect(discoveredPaths(files), ['lib/root.dart']);
      expect(files.skippedFiles, isEmpty);
      expect(skippedDirectoryFacts(files), [
        (path: 'repos/nested', reason: FileSkipReason.nestedRepository),
        (path: 'worktrees/checkout', reason: FileSkipReason.nestedRepository),
      ]);
    });

    test('does not inspect Dart files inside skipped directories', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/source.dart', 'void source() {}');
      writeFile(root, 'build/generated.g.dart', 'not valid dart');

      final files = discoverTargetPackageFiles(root);

      expect(discoveredPaths(files), ['lib/source.dart']);
      expect(files.skippedFiles, isEmpty);
      expect(skippedDirectoryFacts(files), [
        (path: 'build', reason: FileSkipReason.excludedDirectory),
      ]);
    });

    test('orders discovered and skipped files by relative path', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'test/z_test.dart', 'void z() {}');
      writeFile(root, 'lib/a.dart', 'void a() {}');
      writeFile(root, 'lib/z.g.dart', 'void zGenerated() {}');
      writeFile(root, '.dart_tool/b.dart', 'void b() {}');

      final files = discoverTargetPackageFiles(root);

      expect(discoveredPaths(files), ['lib/a.dart', 'test/z_test.dart']);
      expect(skippedFileFacts(files), [
        (path: 'lib/z.g.dart', reason: FileSkipReason.generatedFile),
      ]);
      expect(skippedDirectoryFacts(files), [
        (path: '.dart_tool', reason: FileSkipReason.excludedDirectory),
      ]);
    });
  });
}
