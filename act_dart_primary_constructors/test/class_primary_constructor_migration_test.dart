import 'dart:convert';

import 'package:act_dart_primary_constructors/act_dart_primary_constructors.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('class primary constructor migration', () {
    test('migrates final field-formal parameters', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/user.dart', '''
class User {
  final String id;
  final int age;

  User(this.id, this.age);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

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
      expect(await formattedFile(root, 'lib/user.dart'), '''
class User(final String id, final int age);
''');
    });

    test('migrates mutable field-formal parameters', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/counter.dart', '''
class Counter {
  int count;

  Counter(this.count);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      expect(await formattedFile(root, 'lib/counter.dart'), '''
class Counter(var int count);
''');
    });

    test('preserves const constructors as explicit primary const', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/palette.dart', '''
class Palette {
  final String primary;

  const Palette(this.primary);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      expect(await formattedFile(root, 'lib/palette.dart'), '''
class const Palette(final String primary);
''');
    });

    test('preserves named parameters and required markers', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/person.dart', '''
class Person {
  final String name;
  final int age;

  Person({required this.name, this.age = 0});
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/person.dart',
        declarationName: 'Person',
      );
      expect(await formattedFile(root, 'lib/person.dart'), '''
class Person({required final String name, final int age = 0});
''');
    });

    test('preserves optional positional parameters and defaults', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/range.dart', '''
class Range {
  final int start;
  final int end;

  Range([this.start = 0, this.end = 10]);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/range.dart',
        declarationName: 'Range',
      );
      expect(await formattedFile(root, 'lib/range.dart'), '''
class Range([final int start = 0, final int end = 10]);
''');
    });

    test('preserves positional order and named grouping', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/item.dart', '''
class Item {
  final int id;
  final String name;
  final bool active;

  Item(this.id, {required this.name, this.active = true});
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/item.dart',
        declarationName: 'Item',
      );
      expect(await formattedFile(root, 'lib/item.dart'), '''
class Item(
  final int id, {
  required final String name,
  final bool active = true,
});
''');
    });

    test('preserves type parameters modifiers and clauses', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/box.dart', '''
abstract class Box<T extends Object> extends Base<T> implements Named {
  final T value;

  Box(this.value);
}

abstract class Base<T> {}

abstract class Named {}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/box.dart',
        declarationName: 'Box',
      );
      expect(await formattedFile(root, 'lib/box.dart'), '''
abstract class Box<T extends Object>(final T value)
    extends Base<T>
    implements Named;

abstract class Base<T> {}

abstract class Named {}
''');
    });

    test('migrates private field-formal parameters', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/secret.dart', '''
class _Secret {
  final String _value;

  _Secret(this._value);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/secret.dart',
        declarationName: '_Secret',
      );
      expect(await formattedFile(root, 'lib/secret.dart'), '''
class _Secret(final String _value);
''');
    });

    test('migrates mixed field-to-parameter declarations', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/profile.dart', '''
class Profile {
  /// Public identifier.
  final String id;
  final String _token;
  int visits;

  Profile(this.id, this._token, this.visits);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/profile.dart',
        declarationName: 'Profile',
      );
      expect(await formattedFile(root, 'lib/profile.dart'), '''
class Profile(
  /// Public identifier.
  final String id,
  final String _token,
  var int visits,
);
''');
    });

    test('preserves public names for private named fields', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/session.dart', '''
class Session {
  final String _id;

  Session({required String id}) : _id = id;
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/session.dart',
        declarationName: 'Session',
      );
      expect(await formattedFile(root, 'lib/session.dart'), '''
class Session({required final String _id});
''');
    });

    test('preserves simple super parameters unchanged', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/tile.dart', '''
class Tile extends Widget {
  final String title;

  Tile(super.key, this.title);
}

class Widget {
  Widget(Object? key);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/tile.dart',
        declarationName: 'Tile',
      );
      expect(await formattedFile(root, 'lib/tile.dart'), '''
class Tile(super.key, final String title) extends Widget;

class Widget {
  Widget(Object? key);
}
''');
    });

    test(
      'keeps explicit parentheses for zero-parameter const constructors',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/marker.dart', '''
class Marker {
  const Marker();
}
''');

        final result = await runCli(['migrate', '--root', root.path, '--json']);

        expectSinglePrimaryConstructorMigration(
          result,
          path: 'lib/marker.dart',
          declarationName: 'Marker',
        );
        expect(await formattedFile(root, 'lib/marker.dart'), '''
class const Marker();
''');
      },
    );

    test('collapses empty non-const constructor boilerplate', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/empty.dart', '''
class Empty {
  Empty();
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/empty.dart',
        declarationName: 'Empty',
      );
      expect(await formattedFile(root, 'lib/empty.dart'), '''
class Empty;
''');
    });

    test('dry run reports migrations without writing files', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
class User {
  final String id;

  User(this.id);
}
''';
      writeFile(root, 'lib/user.dart', originalSource);

      final result = await runCli([
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
      expect(readFile(root, 'lib/user.dart'), originalSource);
    });

    test('moves safe initializer-list field assignments to fields', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/score.dart', '''
class Score {
  final int base;
  final int bonus;
  final int total;

  Score(this.base, this.bonus) : total = base + bonus;
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/score.dart',
        declarationName: 'Score',
      );
      expect(await formattedFile(root, 'lib/score.dart'), '''
class Score(final int base, final int bonus) {
  final int total = base + bonus;
}
''');
    });

    test('retains assert initializers in primary constructor body', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/checked.dart', '''
class Checked {
  final String id;

  Checked(this.id) : assert(id.isNotEmpty);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/checked.dart',
        declarationName: 'Checked',
      );
      expect(await formattedFile(root, 'lib/checked.dart'), '''
class Checked(final String id) {
  this : assert(id.isNotEmpty);
}
''');
    });

    test(
      'retains unnamed super initializers in primary constructor body',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/button.dart', '''
class Button extends Widget {
  final String label;

  Button(this.label) : super(label);
}

class Widget {
  Widget(Object label);
}
''');

        final result = await runCli(['migrate', '--root', root.path, '--json']);

        expectSinglePrimaryConstructorMigration(
          result,
          path: 'lib/button.dart',
          declarationName: 'Button',
        );
        expect(await formattedFile(root, 'lib/button.dart'), '''
class Button(final String label) extends Widget {
  this : super(label);
}

class Widget {
  Widget(Object label);
}
''');
      },
    );

    test('preserves retained initializer relative order', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/ordered.dart', '''
class Ordered extends Base {
  final int value;
  final int doubled;

  Ordered(this.value)
      : assert(value > 0),
        doubled = value * 2,
        super(value),
        assert(value.isFinite);
}

class Base {
  Base(Object value);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/ordered.dart',
        declarationName: 'Ordered',
      );
      expect(await formattedFile(root, 'lib/ordered.dart'), '''
class Ordered(final int value) extends Base {
  final int doubled = value * 2;

  this : assert(value > 0), super(value), assert(value.isFinite);
}

class Base {
  Base(Object value);
}
''');
    });

    test('moves safe non-empty constructor bodies to primary bodies', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/guarded.dart', '''
class Guarded {
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
        declarationName: 'Guarded',
      );
      expect(await formattedFile(root, 'lib/guarded.dart'), '''
class Guarded(final String id) {
  this {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id');
    }
    print(id);
  }
}
''');
    });

    test(
      'moves directly attached documentation comments to parameters',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        writeFile(root, 'lib/documented.dart', '''
class Documented {
  /// Stable identifier.
  final String id;

  Documented(this.id);
}
''');

        final result = await runCli(['migrate', '--root', root.path, '--json']);

        expectSinglePrimaryConstructorMigration(
          result,
          path: 'lib/documented.dart',
          declarationName: 'Documented',
        );
        expect(await formattedFile(root, 'lib/documented.dart'), '''
class Documented(
  /// Stable identifier.
  final String id,
);
''');
      },
    );

    test('moves directly attached line comments to parameters', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/line_commented.dart', '''
class LineCommented {
  // Stable identifier.
  final String id;

  LineCommented(this.id);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/line_commented.dart',
        declarationName: 'LineCommented',
      );
      expect(await formattedFile(root, 'lib/line_commented.dart'), '''
class LineCommented(
  // Stable identifier.
  final String id,
);
''');
    });

    test('moves directly attached block comments to parameters', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFile(root, 'lib/block_commented.dart', '''
class BlockCommented {
  /*
   * Stable identifier.
   */
  final String id;

  BlockCommented(this.id);
}
''');

      final result = await runCli(['migrate', '--root', root.path, '--json']);

      expectSinglePrimaryConstructorMigration(
        result,
        path: 'lib/block_commented.dart',
        declarationName: 'BlockCommented',
      );
      expect(await formattedFile(root, 'lib/block_commented.dart'), '''
class BlockCommented(
  /*
   * Stable identifier.
   */
  final String id,
);
''');
    });
  });
}
