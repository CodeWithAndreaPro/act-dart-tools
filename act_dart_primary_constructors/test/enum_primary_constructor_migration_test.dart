import 'dart:convert';

import 'package:act_dart_primary_constructors/act_dart_primary_constructors.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('enum primary constructor migration', () {
    test('migrates positional field-formal constructors', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/status.dart', '''
enum HttpStatus {
  ok(200),
  notFound(404);

  final int code;

  const HttpStatus(this.code);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/status.dart',
        declarationKind: 'enum',
        declarationName: 'HttpStatus',
      );
      expect(await formattedFile(root, 'lib/status.dart'), '''
enum HttpStatus(final int code) {
  ok(200),
  notFound(404);
}
''');
    });

    test('migrates named field-formal constructors', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/button_size.dart', '''
enum ButtonSize {
  small(label: 'Small'),
  large(label: 'Large');

  final String label;

  const ButtonSize({required this.label});
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/button_size.dart',
        declarationKind: 'enum',
        declarationName: 'ButtonSize',
      );
      expect(await formattedFile(root, 'lib/button_size.dart'), '''
enum ButtonSize({required final String label}) {
  small(label: 'Small'),
  large(label: 'Large');
}
''');
    });

    test('migrates mixed positional and named parameter groups', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/token_kind.dart', '''
enum TokenKind {
  keyword('keyword', index: 0, terminal: true),
  identifier('identifier', index: 1);

  final String label;
  final int index;
  final bool terminal;

  const TokenKind(this.label, {required this.index, this.terminal = false});
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/token_kind.dart',
        declarationKind: 'enum',
        declarationName: 'TokenKind',
      );
      expect(await formattedFile(root, 'lib/token_kind.dart'), '''
enum TokenKind(
  final String label, {
  required final int index,
  final bool terminal = false,
}) {
  keyword('keyword', index: 0, terminal: true),
  identifier('identifier', index: 1);
}
''');
    });

    test(
      'preserves retained methods getters factories and static members',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/permission.dart', '''
enum Permission {
  read('r');

  final String code;

  const Permission(this.code);

  String get label => code.toUpperCase();

  bool matches(String value) => value == code;

  factory Permission.fromCode(String code) => read;

  static const defaultValue = read;
}
''');

        final result = await runCli(['migrate', '--root', root.path, '--json']);

        expectSinglePrimaryConstructorMigration(
          result,
          path: 'lib/permission.dart',
          declarationKind: 'enum',
          declarationName: 'Permission',
        );
        expect(await formattedFile(root, 'lib/permission.dart'), '''
enum Permission(final String code) {
  read('r');

  String get label => code.toUpperCase();

  bool matches(String value) => value == code;

  factory Permission.fromCode(String code) => read;

  static const defaultValue = read;
}
''');
      },
    );

    test('moves safe initializer assignments and retains assertions', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/score.dart', '''
enum Score {
  low(1),
  high(10);

  final int base;
  final int doubled;

  const Score(this.base) : doubled = base * 2, assert(base > 0);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/score.dart',
        declarationKind: 'enum',
        declarationName: 'Score',
      );
      expect(await formattedFile(root, 'lib/score.dart'), '''
enum Score(final int base) {
  low(1),
  high(10);

  final int doubled = base * 2;

  this : assert(base > 0);
}
''');
    });

    test('moves safe non-empty constructor bodies', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/guarded.dart', '''
enum Guarded {
  value('id');

  final String id;

  Guarded(this.id) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id');
    }
    print(id);
  }
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/guarded.dart',
        declarationKind: 'enum',
        declarationName: 'Guarded',
      );
      expect(await formattedFile(root, 'lib/guarded.dart'), '''
enum Guarded(final String id) {
  value('id');

  this {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id');
    }
    print(id);
  }
}
''');
    });
  });

  group('enum primary constructor skip reporting', () {
    test('skips unsupported initializer cases precisely', () async {
      const originalSource = '''
enum DuplicateInitializer {
  value(1);

  final int code;

  const DuplicateInitializer(this.code) : code = code;
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/initializer.dart',
        originalSource: originalSource,
        declarationKind: 'enum',
        declarationName: 'DuplicateInitializer',
        reason: 'unsupportedInitializer',
        message: 'This constructor initializer is not supported.',
      );
    });

    test('skips unsafe initializer dependencies precisely', () async {
      const originalSource = '''
enum UnsafeInitializerDependency {
  value(1);

  final int base;
  final int total;

  const UnsafeInitializerDependency(this.base) : total = this.base + 1;
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/initializer_dependency.dart',
        originalSource: originalSource,
        declarationKind: 'enum',
        declarationName: 'UnsafeInitializerDependency',
        reason: 'unsafeInitializerDependency',
        message:
            'Initializer field assignments must depend only on constructor parameters.',
      );
    });

    test('skips assignment-in-body field initialization precisely', () async {
      const originalSource = '''
enum FieldInitializingBody {
  value('id');

  String? id;

  FieldInitializingBody(String id) {
    this.id = id;
  }
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/body_field_initializer.dart',
        originalSource: originalSource,
        declarationKind: 'enum',
        declarationName: 'FieldInitializingBody',
        reason: 'fieldInitializingConstructorBody',
        message:
            'Constructor bodies that initialize instance fields are not supported.',
      );
    });

    test(
      'reports enum migrations as primary constructor enum entries',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/status.dart', '''
enum HttpStatus {
  ok(200);

  final int code;

  const HttpStatus(this.code);
}
''');

        final result = await runCli(['migrate', '--root', root.path, '--json']);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['migratedDeclarations'], [
          {
            'path': 'lib/status.dart',
            'declarationKind': 'enum',
            'declarationName': 'HttpStatus',
            'transform': 'primaryConstructor',
            'offset': 0,
          },
        ]);
      },
    );
  });
}
