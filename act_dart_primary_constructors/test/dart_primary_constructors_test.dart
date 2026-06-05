import 'dart:convert';
import 'dart:io';

import 'package:dart_primary_constructors/dart_primary_constructors.dart';
import 'package:dart_primary_constructors/src/discovery.dart';
import 'package:dart_primary_constructors/src/source_edit.dart';
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

  group('source edits', () {
    test('applies insertions, replacements, and deletions descending', () {
      final result = applySourceEdits('abcdef', const [
        SourceEdit(offset: 1, length: 0, replacement: 'X'),
        SourceEdit(offset: 3, length: 1, replacement: 'Y'),
        SourceEdit(offset: 5, length: 1, replacement: ''),
      ]);

      expect(result, 'aXbcYe');
    });

    test('rejects overlapping edits', () {
      expect(
        () => applySourceEdits('abcdef', const [
          SourceEdit(offset: 1, length: 3, replacement: 'X'),
          SourceEdit(offset: 3, length: 1, replacement: 'Y'),
        ]),
        throwsA(isA<SourceEditException>()),
      );
    });
  });

  group('class primary constructor migration', () {
    test('migrates final field-formal parameters', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/user.dart', '''
class User {
  final String id;
  final int age;

  User(this.id, this.age);
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['changedFiles'], ['lib/user.dart']);
      expect(decoded['migratedDeclarations'], [
        {
          'path': 'lib/user.dart',
          'declarationKind': 'class',
          'declarationName': 'User',
          'transform': 'primaryConstructor',
          'offset': 0,
        },
      ]);
      expect(decoded['transformCounts'], {'primaryConstructor': 1});
      expect(await _formattedFile(root, 'lib/user.dart'), '''
class User(final String id, final int age);
''');
    });

    test('migrates mutable field-formal parameters', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/counter.dart', '''
class Counter {
  int count;

  Counter(this.count);
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      expect(await _formattedFile(root, 'lib/counter.dart'), '''
class Counter(var int count);
''');
    });

    test('preserves const constructors as explicit primary const', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/palette.dart', '''
class Palette {
  final String primary;

  const Palette(this.primary);
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      expect(await _formattedFile(root, 'lib/palette.dart'), '''
class const Palette(final String primary);
''');
    });

    test('preserves named parameters and required markers', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/person.dart', '''
class Person {
  final String name;
  final int age;

  Person({required this.name, this.age = 0});
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      _expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/person.dart',
        declarationName: 'Person',
      );
      expect(await _formattedFile(root, 'lib/person.dart'), '''
class Person({required final String name, final int age = 0});
''');
    });

    test('preserves optional positional parameters and defaults', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/range.dart', '''
class Range {
  final int start;
  final int end;

  Range([this.start = 0, this.end = 10]);
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      _expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/range.dart',
        declarationName: 'Range',
      );
      expect(await _formattedFile(root, 'lib/range.dart'), '''
class Range([final int start = 0, final int end = 10]);
''');
    });

    test('preserves positional order and named grouping', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/item.dart', '''
class Item {
  final int id;
  final String name;
  final bool active;

  Item(this.id, {required this.name, this.active = true});
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      _expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/item.dart',
        declarationName: 'Item',
      );
      expect(await _formattedFile(root, 'lib/item.dart'), '''
class Item(
  final int id, {
  required final String name,
  final bool active = true,
});
''');
    });

    test('preserves type parameters modifiers and clauses', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/box.dart', '''
abstract class Box<T extends Object> extends Base<T> implements Named {
  final T value;

  Box(this.value);
}

abstract class Base<T> {}

abstract class Named {}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      _expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/box.dart',
        declarationName: 'Box',
      );
      expect(await _formattedFile(root, 'lib/box.dart'), '''
abstract class Box<T extends Object>(final T value)
    extends Base<T>
    implements Named;

abstract class Base<T> {}

abstract class Named {}
''');
    });

    test('migrates private field-formal parameters', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/secret.dart', '''
class _Secret {
  final String _value;

  _Secret(this._value);
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      _expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/secret.dart',
        declarationName: '_Secret',
      );
      expect(await _formattedFile(root, 'lib/secret.dart'), '''
class _Secret(final String _value);
''');
    });

    test('preserves public names for private named fields', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/session.dart', '''
class Session {
  final String _id;

  Session({required String id}) : _id = id;
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      _expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/session.dart',
        declarationName: 'Session',
      );
      expect(await _formattedFile(root, 'lib/session.dart'), '''
class Session({required final String _id});
''');
    });

    test('preserves simple super parameters unchanged', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/tile.dart', '''
class Tile extends Widget {
  final String title;

  Tile(super.key, this.title);
}

class Widget {
  Widget(Object? key);
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      _expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/tile.dart',
        declarationName: 'Tile',
      );
      expect(await _formattedFile(root, 'lib/tile.dart'), '''
class Tile(super.key, final String title) extends Widget;

class Widget {
  Widget(Object? key);
}
''');
    });

    test(
      'keeps explicit parentheses for zero-parameter const constructors',
      () async {
        final root = await _createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        _writeFile(root, 'lib/marker.dart', '''
class Marker {
  const Marker();
}
''');

        final result = await _runCli([
          'migrate',
          '--root',
          root.path,
          '--json',
        ]);

        _expectSinglePrimaryConstructorMigration(
          result,
          path: 'lib/marker.dart',
          declarationName: 'Marker',
        );
        expect(await _formattedFile(root, 'lib/marker.dart'), '''
class const Marker();
''');
      },
    );

    test('collapses empty non-const constructor boilerplate', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      _writeFile(root, 'lib/empty.dart', '''
class Empty {
  Empty();
}
''');

      final result = await _runCli(['migrate', '--root', root.path, '--json']);

      _expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/empty.dart',
        declarationName: 'Empty',
      );
      expect(await _formattedFile(root, 'lib/empty.dart'), '''
class Empty;
''');
    });

    test('dry run reports migrations without writing files', () async {
      final root = await _createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
class User {
  final String id;

  User(this.id);
}
''';
      _writeFile(root, 'lib/user.dart', originalSource);

      final result = await _runCli([
        'migrate',
        '--root',
        root.path,
        '--dry-run',
        '--json',
      ]);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['dryRun'], isTrue);
      expect(decoded['changedFiles'], ['lib/user.dart']);
      expect(decoded['transformCounts'], {'primaryConstructor': 1});
      expect(
        File(
          '${root.path}${Platform.pathSeparator}lib/user.dart',
        ).readAsStringSync(),
        originalSource,
      );
    });
  });

  group('class primary constructor skip reporting', () {
    test(
      'omits ordinary non-candidates and already-primary declarations',
      () async {
        final root = await _createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        const originalSource = '''
class Plain {
  void ping() {}
}

class Already(final String id);
''';
        _writeFile(root, 'lib/source.dart', originalSource);

        final result = await _runCli([
          'migrate',
          '--root',
          root.path,
          '--json',
        ]);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['ok'], isTrue);
        expect(decoded['changedFiles'], isEmpty);
        expect(decoded['migratedDeclarations'], isEmpty);
        expect(decoded['skippedDeclarations'], isEmpty);
        expect(decoded['skipReasonCounts'], isEmpty);
        expect(_readFile(root, 'lib/source.dart'), originalSource);
      },
    );

    for (final scenario in [
      (
        name: 'named constructor',
        declarationName: 'NamedConstructor',
        reason: 'namedConstructor',
        message: 'Named generative constructors are not supported.',
        source: '''
class NamedConstructor {
  final String id;

  NamedConstructor(this.id);

  NamedConstructor.create(this.id);
}
''',
      ),
      (
        name: 'redirecting constructor',
        declarationName: 'RedirectingConstructor',
        reason: 'redirectingConstructor',
        message: 'Redirecting constructors are not supported.',
        source: '''
class RedirectingConstructor {
  RedirectingConstructor() : this.named();

  RedirectingConstructor.named();
}
''',
      ),
      (
        name: 'non-empty constructor body',
        declarationName: 'BodyConstructor',
        reason: 'nonEmptyConstructorBody',
        message: 'Non-empty constructor bodies are not supported.',
        source: '''
class BodyConstructor {
  final String id;

  BodyConstructor(this.id) {
    print(id);
  }
}
''',
      ),
    ]) {
      test('skips unsafe ${scenario.name} shape precisely', () async {
        await _expectSinglePrimaryConstructorSkip(
          relativePath: 'lib/unsafe.dart',
          originalSource: scenario.source,
          declarationName: scenario.declarationName,
          reason: scenario.reason,
          message: scenario.message,
        );
      });
    }

    for (final scenario in [
      (
        name: 'constructor metadata',
        declarationName: 'ConstructorMetadata',
        reason: 'constructorMetadata',
        message: 'Constructor metadata is not moved to primary constructors.',
        source: '''
class ConstructorMetadata {
  final String id;

  @deprecated
  ConstructorMetadata(this.id);
}
''',
      ),
      (
        name: 'parameter metadata',
        declarationName: 'ParameterMetadata',
        reason: 'parameterMetadata',
        message: 'Parameter metadata is not moved to declaring parameters.',
        source: '''
class ParameterMetadata {
  final String id;

  ParameterMetadata(@deprecated this.id);
}
''',
      ),
      (
        name: 'field metadata',
        declarationName: 'FieldMetadata',
        reason: 'fieldMetadata',
        message: 'Field metadata is not moved to declaring parameters.',
        source: '''
class FieldMetadata {
  @deprecated
  final String id;

  FieldMetadata(this.id);
}
''',
      ),
    ]) {
      test('skips ${scenario.name} precisely', () async {
        await _expectSinglePrimaryConstructorSkip(
          relativePath: 'lib/metadata.dart',
          originalSource: scenario.source,
          declarationName: scenario.declarationName,
          reason: scenario.reason,
          message: scenario.message,
        );
      });
    }

    for (final scenario in [
      (
        name: 'missing mapped field',
        declarationName: 'MissingMappedField',
        reason: 'missingField',
        message: 'A constructor parameter maps to a missing field.',
        source: '''
class MissingMappedField {
  MissingMappedField(this.id);
}
''',
      ),
      (
        name: 'static mapped field',
        declarationName: 'StaticMappedField',
        reason: 'staticField',
        message: 'Static fields cannot become declaring parameters.',
        source: '''
class StaticMappedField {
  static final String id = '';

  StaticMappedField(this.id);
}
''',
      ),
      (
        name: 'late mapped field',
        declarationName: 'LateMappedField',
        reason: 'lateField',
        message: 'Late fields cannot become declaring parameters.',
        source: '''
class LateMappedField {
  late final String id;

  LateMappedField(this.id);
}
''',
      ),
      (
        name: 'external mapped field',
        declarationName: 'ExternalMappedField',
        reason: 'externalField',
        message: 'External fields cannot become declaring parameters.',
        source: '''
class ExternalMappedField {
  external final String id;

  ExternalMappedField(this.id);
}
''',
      ),
      (
        name: 'initialized mapped field',
        declarationName: 'InitializedMappedField',
        reason: 'initializedField',
        message: 'Initialized fields cannot become declaring parameters.',
        source: '''
class InitializedMappedField {
  final String id = '';

  InitializedMappedField(this.id);
}
''',
      ),
      (
        name: 'implicit-type mapped field',
        declarationName: 'ImplicitMappedField',
        reason: 'implicitFieldType',
        message:
            'Fields with implicit types cannot become declaring parameters.',
        source: '''
class ImplicitMappedField {
  var id;

  ImplicitMappedField(this.id);
}
''',
      ),
      (
        name: 'multi-variable mapped field',
        declarationName: 'MultiVariableMappedField',
        reason: 'multipleFieldVariables',
        message:
            'Multi-variable field declarations cannot become declaring parameters.',
        source: '''
class MultiVariableMappedField {
  final String id, name;

  MultiVariableMappedField(this.id);
}
''',
      ),
    ]) {
      test('skips ${scenario.name} precisely', () async {
        await _expectSinglePrimaryConstructorSkip(
          relativePath: 'lib/field.dart',
          originalSource: scenario.source,
          declarationName: scenario.declarationName,
          reason: scenario.reason,
          message: scenario.message,
        );
      });
    }

    test('skips unsupported parameter shapes precisely', () async {
      const originalSource = '''
class UnsupportedParameter {
  final String id;

  UnsupportedParameter(String id);
}
''';

      await _expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/parameter.dart',
        originalSource: originalSource,
        declarationName: 'UnsupportedParameter',
        reason: 'unsupportedParameterShape',
        message: 'This constructor parameter shape is not supported.',
      );
    });

    test('skips unsupported initializer cases precisely', () async {
      const originalSource = '''
class UnsupportedInitializer {
  final String id;

  UnsupportedInitializer(this.id) : assert(id.isNotEmpty);
}
''';

      await _expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/initializer.dart',
        originalSource: originalSource,
        declarationName: 'UnsupportedInitializer',
        reason: 'unsupportedInitializer',
        message: 'This constructor initializer is not supported.',
      );
    });

    test('skips named super initializer cases precisely', () async {
      const originalSource = '''
class Child extends Parent {
  final String id;

  Child(this.id) : super.named();
}

class Parent {
  Parent.named();
}
''';

      await _expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/super.dart',
        originalSource: originalSource,
        declarationName: 'Child',
        reason: 'namedSuperInitializer',
        message: 'Named super constructor initializers are not supported.',
      );
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

Map<String, Object?> _expectSinglePrimaryConstructorMigration(
  ProcessResult result, {
  required String path,
  required String declarationName,
}) {
  expect(result.exitCode, exitSuccess);
  expect(result.stderr, isEmpty);
  final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
  expect(decoded['changedFiles'], [path]);
  expect(decoded['migratedDeclarations'], [
    {
      'path': path,
      'declarationKind': 'class',
      'declarationName': declarationName,
      'transform': 'primaryConstructor',
      'offset': 0,
    },
  ]);
  expect(decoded['transformCounts'], {'primaryConstructor': 1});
  return decoded;
}

Future<Map<String, Object?>> _expectSinglePrimaryConstructorSkip({
  required String relativePath,
  required String originalSource,
  required String declarationName,
  required String reason,
  required String message,
}) async {
  final root = await _createPackageRoot();
  addTearDown(() => root.deleteSync(recursive: true));
  _writeFile(root, relativePath, originalSource);

  final result = await _runCli(['migrate', '--root', root.path, '--json']);

  expect(result.exitCode, exitSuccess);
  expect(result.stderr, isEmpty);
  final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
  expect(decoded['ok'], isTrue);
  expect(decoded['changedFiles'], isEmpty);
  expect(decoded['migratedDeclarations'], isEmpty);
  expect(decoded['skippedDeclarations'], [
    {
      'path': relativePath,
      'declarationKind': 'class',
      'declarationName': declarationName,
      'transform': 'primaryConstructor',
      'offset': 0,
      'reason': reason,
      'message': message,
    },
  ]);
  expect(decoded['skipReasonCounts'], {reason: 1});
  expect(_readFile(root, relativePath), originalSource);
  return decoded;
}

Future<String> _formattedFile(Directory root, String relativePath) async {
  final file = File(
    '${root.path}${Platform.pathSeparator}${_systemPath(relativePath)}',
  );
  final result = await Process.run(Platform.resolvedExecutable, [
    'format',
    '--enable-experiment=primary-constructors',
    file.path,
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return file.readAsStringSync();
}

String _readFile(Directory root, String relativePath) {
  return File(
    '${root.path}${Platform.pathSeparator}${_systemPath(relativePath)}',
  ).readAsStringSync();
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
