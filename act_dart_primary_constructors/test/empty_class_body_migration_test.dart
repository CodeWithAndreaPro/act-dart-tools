import 'dart:convert';

import 'package:act_dart_primary_constructors/act_dart_primary_constructors.dart';
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

      final result = await runCli(['migrate', '--root', root.path, '--json']);

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

      final result = await runCli(['migrate', '--root', root.path, '--json']);

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

        final result = await runCli(['migrate', '--root', root.path, '--json']);

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

      final result = await runCli(['migrate', '--root', root.path, '--json']);

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

      final result = await runCli(['migrate', '--root', root.path, '--json']);

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

    test('does not collapse enums mixins or extension types', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
enum Choice { one }

mixin EmptyMixin {}

extension type Identifier(String value) {}
''';
      writeFile(root, 'lib/unsupported.dart', originalSource);

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['changedFiles'], isEmpty);
      expect(decoded['migratedDeclarations'], isEmpty);
      expect(decoded['skippedDeclarations'], isEmpty);
      expect(readFile(root, 'lib/unsupported.dart'), originalSource);
    });
  });
}
