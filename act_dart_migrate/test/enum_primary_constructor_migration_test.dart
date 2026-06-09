import 'dart:convert';

import 'package:act_dart_migrate/act_dart_migrate.dart';
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

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

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

    test('preserves optional positional field-formal defaults', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/severity.dart', '''
enum SeverityProbe {
  low(),
  high(2);

  final int level;

  const SeverityProbe([this.level = 1]);
}
''');

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/severity.dart',
        declarationKind: 'enum',
        declarationName: 'SeverityProbe',
      );
      expect(await formattedFile(root, 'lib/severity.dart'), '''
enum SeverityProbe([final int level = 1]) {
  low(),
  high(2);
}
''');
    });

    test('migrates multi-variable fields when all variables map', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/enum_multi_variable.dart', '''
enum EnumMultiVariableProbe {
  one(1, 10);

  final int code, weight;

  const EnumMultiVariableProbe(this.code, this.weight);
}
''');

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/enum_multi_variable.dart',
        declarationKind: 'enum',
        declarationName: 'EnumMultiVariableProbe',
      );
      expect(await formattedFile(root, 'lib/enum_multi_variable.dart'), '''
enum EnumMultiVariableProbe(final int code, final int weight) {
  one(1, 10);
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

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

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

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

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

        final result = await runCli([
          'primary-constructors',
          root.path,
          '--json',
        ]);

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

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

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

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

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
    test('skips field metadata precisely', () async {
      const originalSource = '''
enum EnumFieldMetadataProbe {
  one('1');

  @Deprecated('fixture')
  final String id;

  const EnumFieldMetadataProbe(this.id);
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/enum_metadata.dart',
        originalSource: originalSource,
        declarationKind: 'enum',
        declarationName: 'EnumFieldMetadataProbe',
        reason: 'fieldMetadata',
        message: 'Field metadata is not moved to declaring parameters.',
      );
    });

    for (final scenario in [
      (
        name: 'partial multi-variable fields',
        declarationName: 'EnumPartialMultiVariableProbe',
        source: '''
enum EnumPartialMultiVariableProbe {
  one(1);

  final int code, weight;

  const EnumPartialMultiVariableProbe(this.code);
}
''',
        reason: 'multipleFieldVariables',
        message:
            'Multi-variable field declarations cannot become declaring parameters.',
      ),
      (
        name: 'trailing field comments',
        declarationName: 'EnumTrailingFieldCommentProbe',
        source: '''
enum EnumTrailingFieldCommentProbe {
  one('1');

  final String id; // Stable identifier.

  const EnumTrailingFieldCommentProbe(this.id);
}
''',
        reason: 'fieldComment',
        message:
            'Ambiguous field comments are not moved to declaring parameters.',
      ),
    ]) {
      test('skips ${scenario.name} precisely', () async {
        await expectSinglePrimaryConstructorSkip(
          relativePath: 'lib/enum_field.dart',
          originalSource: scenario.source,
          declarationKind: 'enum',
          declarationName: scenario.declarationName,
          reason: scenario.reason,
          message: scenario.message,
        );
      });
    }

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

    test('skips moved initializers before existing field initializers', () async {
      const originalSource = '''
enum OrderedInitializers {
  value(1);

  final int base;
  final int doubled;
  final int existing = 0;

  const OrderedInitializers(this.base) : doubled = base * 2;
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/initializer_order.dart',
        originalSource: originalSource,
        declarationKind: 'enum',
        declarationName: 'OrderedInitializers',
        reason: 'unsafeInitializerOrder',
        message:
            'Moving initializer field assignments would change initializer evaluation order.',
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

        final result = await runCli([
          'primary-constructors',
          root.path,
          '--json',
        ]);

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
