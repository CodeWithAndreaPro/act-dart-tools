import 'dart:convert';

import 'package:act_dart_migrate/src/core/exit_codes.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('empty class body migration', () {
    test('collapses standalone empty ordinary class bodies', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/empty.dart', '''
class Empty {}
''');

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['changedFiles'], ['lib/empty.dart']);
      expect(decoded['migratedDeclarations'], [
        {
          'path': 'lib/empty.dart',
          'declarationKind': 'class',
          'declarationName': 'Empty',
          'transform': 'emptyClassBody',
          'offset': 0,
        },
      ]);
      expect(decoded['transformCounts'], {'emptyClassBody': 1});
      expect(await formattedFile(root, 'lib/empty.dart'), '''
class Empty;
''');
    });

    test('treats existing semicolon class bodies as no-ops', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
class AlreadyEmpty;

sealed class DatabaseIOResult;

class DatabaseIOSuccess({final String? path}) extends DatabaseIOResult;

class DatabaseIOError(final String message) extends DatabaseIOResult;
''';
      writeFile(root, 'lib/already_empty.dart', originalSource);

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['changedFiles'], isEmpty);
      expect(decoded['migratedDeclarations'], isEmpty);
      expect(decoded['skippedDeclarations'], isEmpty);
      expect(decoded['transformCounts'], isEmpty);
      expect(decoded['skipReasonCounts'], isEmpty);
      expect(readFile(root, 'lib/already_empty.dart'), originalSource);
    });

    test(
      'reports empty body collapse separately after primary migration',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/user.dart', '''
class User {
  final String id;

  User(this.id);
}
''');

        final result = await runCliPrimaryConstructors(root.path);

        expectSinglePrimaryConstructorMigration(
          result,
          path: 'lib/user.dart',
          declarationName: 'User',
          reportsEmptyClassBody: true,
        );
        expect(await formattedFile(root, 'lib/user.dart'), '''
class User(final String id);
''');
      },
    );

    test('preserves modifiers type parameters bounds and clauses', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/leaf.dart', '''
final class Leaf<T extends Object> extends Base<T> implements Named {}

class Base<T> {
  void keep() {}
}

class Named {
  void keep() {}
}
''');

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['migratedDeclarations'], [
        {
          'path': 'lib/leaf.dart',
          'declarationKind': 'class',
          'declarationName': 'Leaf',
          'transform': 'emptyClassBody',
          'offset': 0,
        },
      ]);
      expect(await formattedFile(root, 'lib/leaf.dart'), '''
final class Leaf<T extends Object> extends Base<T> implements Named;

class Base<T> {
  void keep() {}
}

class Named {
  void keep() {}
}
''');
    });

    test('skips empty class bodies with comments precisely', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
class Commented {
  // Keep this note.
}
''';
      writeFile(root, 'lib/commented.dart', originalSource);

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['changedFiles'], isEmpty);
      expect(decoded['migratedDeclarations'], isEmpty);
      expect(decoded['skippedDeclarations'], [
        {
          'path': 'lib/commented.dart',
          'declarationKind': 'class',
          'declarationName': 'Commented',
          'transform': 'emptyClassBody',
          'offset': 0,
          'reason': 'classBodyComment',
          'message': 'Empty class bodies with comments are not collapsed.',
        },
      ]);
      expect(decoded['skipReasonCounts'], {'classBodyComment': 1});
      expect(readFile(root, 'lib/commented.dart'), originalSource);
    });

    test('collapses empty bodies across supported declaration kinds', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
enum Choice { one }

mixin EmptyMixin {}

mixin class EmptyMixinClass {}

extension type Identifier(String value) {}

extension NumberParsing on String {}

enum EmptyEnum {}
''';
      writeFile(root, 'lib/supported_empty_bodies.dart', originalSource);

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['changedFiles'], ['lib/supported_empty_bodies.dart']);
      expect(decoded['migratedDeclarations'], [
        {
          'path': 'lib/supported_empty_bodies.dart',
          'declarationKind': 'mixin',
          'declarationName': 'EmptyMixin',
          'transform': 'emptyClassBody',
          'offset': originalSource.indexOf('mixin EmptyMixin'),
        },
        {
          'path': 'lib/supported_empty_bodies.dart',
          'declarationKind': 'mixinClass',
          'declarationName': 'EmptyMixinClass',
          'transform': 'emptyClassBody',
          'offset': originalSource.indexOf('mixin class EmptyMixinClass'),
        },
        {
          'path': 'lib/supported_empty_bodies.dart',
          'declarationKind': 'extensionType',
          'declarationName': 'Identifier',
          'transform': 'emptyClassBody',
          'offset': originalSource.indexOf('extension type Identifier'),
        },
        {
          'path': 'lib/supported_empty_bodies.dart',
          'declarationKind': 'extension',
          'declarationName': 'NumberParsing',
          'transform': 'emptyClassBody',
          'offset': originalSource.indexOf('extension NumberParsing'),
        },
        {
          'path': 'lib/supported_empty_bodies.dart',
          'declarationKind': 'enum',
          'declarationName': 'EmptyEnum',
          'transform': 'emptyClassBody',
          'offset': originalSource.indexOf('enum EmptyEnum'),
        },
      ]);
      expect(decoded['transformCounts'], {'emptyClassBody': 5});
      expect(await formattedFile(root, 'lib/supported_empty_bodies.dart'), '''
enum Choice { one }

mixin EmptyMixin;

mixin class EmptyMixinClass;

extension type Identifier(String value);

extension NumberParsing on String;

enum EmptyEnum;
''');
    });

    test('rewrites extension type body constructors to shorthand', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
extension type Identifier(String value) {
  Identifier.named(String value) : this(value);
}
''';
      writeFile(root, 'lib/identifier.dart', originalSource);

      final result = await runCliPrimaryConstructors(root.path);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['migratedDeclarations'], [
        {
          'path': 'lib/identifier.dart',
          'declarationKind': 'constructor',
          'declarationName': 'Identifier.named',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf('Identifier.named'),
        },
      ]);
      expect(await formattedFile(root, 'lib/identifier.dart'), '''
extension type Identifier(String value) {
  new named(String value) : this(value);
}
''');
      await expectAnalyzerClean(root);
    });
  });
}
