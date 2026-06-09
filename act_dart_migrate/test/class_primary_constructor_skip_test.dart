import 'dart:convert';

import 'package:act_dart_migrate/act_dart_migrate.dart';
import 'package:test/test.dart';

import 'src/test_support.dart';

void main() {
  group('class primary constructor skip reporting', () {
    test(
      'omits ordinary non-candidates and already-primary declarations',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        const originalSource = '''
class Plain {
  void ping() {}
}

class Already(final String id);
''';
        writeFile(root, 'lib/source.dart', originalSource);

        final result = await runCli([
          'primary-constructors',
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
        expect(readFile(root, 'lib/source.dart'), originalSource);
      },
    );

    test(
      'classifies primary-constructor skip and no-op outcomes in one run',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        const originalSource = '''
class Migrated {
  final String id;

  Migrated(this.id);
}

class Skipped {
  final String id;

  Skipped(String id);
}

class Plain {
  void ping() {}
}

class Already(final String id);
''';
        writeFile(root, 'lib/source.dart', originalSource);

        final result = await runCli([
          'primary-constructors',
          root.path,
          '--json',
        ]);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['changedFiles'], ['lib/source.dart']);
        expect(decoded['migratedDeclarations'], [
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'Migrated',
            'transform': 'primaryConstructor',
            'offset': originalSource.indexOf('class Migrated'),
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'Migrated',
            'transform': 'emptyClassBody',
            'offset': originalSource.indexOf('class Migrated'),
          },
        ]);
        expect(decoded['skippedDeclarations'], [
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'Skipped',
            'transform': 'primaryConstructor',
            'offset': originalSource.indexOf('class Skipped'),
            'reason': 'unsupportedParameterShape',
            'message': 'This constructor parameter shape is not supported.',
          },
        ]);
        expect(decoded['transformCounts'], {
          'primaryConstructor': 1,
          'emptyClassBody': 1,
        });
        expect(decoded['skipReasonCounts'], {'unsupportedParameterShape': 1});
        expect(await formattedFile(root, 'lib/source.dart'), '''
class Migrated(final String id);

class Skipped {
  final String id;

  Skipped(String id);
}

class Plain {
  void ping() {}
}

class Already(final String id);
''');
      },
    );

    test(
      'reports migrated, skipped, and no-op classes from one file in source order',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        const originalSource = '''
class PlainBefore {
  void ping() {}
}

class FirstSkipped {
  final String id;

  FirstSkipped(String id);
}

class FirstMigrated {
  final String id;

  FirstMigrated(this.id);
}

class AlreadyBetween(final String id);

class SecondSkipped {
  final String id;

  SecondSkipped(String id);
}

class SecondMigrated {
  final String id;

  SecondMigrated(this.id);
}

class PlainAfter {
  void pong() {}
}
''';
        writeFile(root, 'lib/source.dart', originalSource);

        final result = await runCli([
          'primary-constructors',
          root.path,
          '--json',
        ]);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['changedFiles'], ['lib/source.dart']);
        expect(decoded['migratedDeclarations'], [
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'FirstMigrated',
            'transform': 'primaryConstructor',
            'offset': originalSource.indexOf('class FirstMigrated'),
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'FirstMigrated',
            'transform': 'emptyClassBody',
            'offset': originalSource.indexOf('class FirstMigrated'),
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'SecondMigrated',
            'transform': 'primaryConstructor',
            'offset': originalSource.indexOf('class SecondMigrated'),
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'SecondMigrated',
            'transform': 'emptyClassBody',
            'offset': originalSource.indexOf('class SecondMigrated'),
          },
        ]);
        expect(decoded['skippedDeclarations'], [
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'FirstSkipped',
            'transform': 'primaryConstructor',
            'offset': originalSource.indexOf('class FirstSkipped'),
            'reason': 'unsupportedParameterShape',
            'message': 'This constructor parameter shape is not supported.',
          },
          {
            'path': 'lib/source.dart',
            'declarationKind': 'class',
            'declarationName': 'SecondSkipped',
            'transform': 'primaryConstructor',
            'offset': originalSource.indexOf('class SecondSkipped'),
            'reason': 'unsupportedParameterShape',
            'message': 'This constructor parameter shape is not supported.',
          },
        ]);
        expect(decoded['transformCounts'], {
          'primaryConstructor': 2,
          'emptyClassBody': 2,
        });
        expect(decoded['skipReasonCounts'], {'unsupportedParameterShape': 2});
        expect(await formattedFile(root, 'lib/source.dart'), '''
class PlainBefore {
  void ping() {}
}

class FirstSkipped {
  final String id;

  FirstSkipped(String id);
}

class FirstMigrated(final String id);

class AlreadyBetween(final String id);

class SecondSkipped {
  final String id;

  SecondSkipped(String id);
}

class SecondMigrated(final String id);

class PlainAfter {
  void pong() {}
}
''');
      },
    );

    for (final scenario in [
      (
        name: 'trailing field comment',
        declarationName: 'TrailingFieldComment',
        source: '''
class TrailingFieldComment {
  final String id; // Stable identifier.

  TrailingFieldComment(this.id);
}
''',
      ),
      (
        name: 'separated field comment',
        declarationName: 'SeparatedFieldComment',
        source: '''
class SeparatedFieldComment {
  // Stable identifier.

  final String id;

  SeparatedFieldComment(this.id);
}
''',
      ),
      (
        name: 'shared field comment',
        declarationName: 'SharedFieldComment',
        source: '''
class SharedFieldComment {
  // Shared identity fields.
  final String id;
  final String name;

  SharedFieldComment(this.id, this.name);
}
''',
      ),
      (
        name: 'interleaved field comment',
        declarationName: 'InterleavedFieldComment',
        source: '''
class InterleavedFieldComment {
  final String id;
  // Interleaved comment.

  InterleavedFieldComment(this.id);
}
''',
      ),
    ]) {
      test('skips ${scenario.name} precisely', () async {
        await expectSinglePrimaryConstructorSkip(
          relativePath: 'lib/comments.dart',
          originalSource: scenario.source,
          declarationName: scenario.declarationName,
          reason: 'fieldComment',
          message:
              'Ambiguous field comments are not moved to declaring parameters.',
        );
      });
    }

    test('skips ambiguous private field comments precisely', () async {
      const originalSource = '''
class PrivateFieldComment {
  final String _id; // Private identifier.

  PrivateFieldComment(this._id);
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/private_comment.dart',
        originalSource: originalSource,
        declarationName: 'PrivateFieldComment',
        reason: 'fieldComment',
        message:
            'Ambiguous field comments are not moved to declaring parameters.',
      );
    });

    test('rewrites named-only constructors without a primary skip', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
class AddInvestmentChoice {
  const AddInvestmentChoice._({this.apiSymbol});

  const AddInvestmentChoice.custom() : this._();

  const AddInvestmentChoice.apiBacked(SupportedApiSymbol symbol) : this._(apiSymbol: symbol);

  final SupportedApiSymbol? apiSymbol;

  bool get isApiBacked => apiSymbol != null;
  bool get isCustom => apiSymbol == null;
}
''';
      writeFile(root, 'lib/add_investment_choice.dart', originalSource);

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['changedFiles'], ['lib/add_investment_choice.dart']);
      expect(decoded['migratedDeclarations'], [
        {
          'path': 'lib/add_investment_choice.dart',
          'declarationKind': 'constructor',
          'declarationName': 'AddInvestmentChoice._',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf('const AddInvestmentChoice._'),
        },
        {
          'path': 'lib/add_investment_choice.dart',
          'declarationKind': 'constructor',
          'declarationName': 'AddInvestmentChoice.custom',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf('const AddInvestmentChoice.custom'),
        },
        {
          'path': 'lib/add_investment_choice.dart',
          'declarationKind': 'constructor',
          'declarationName': 'AddInvestmentChoice.apiBacked',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf(
            'const AddInvestmentChoice.apiBacked',
          ),
        },
      ]);
      expect(decoded['skippedDeclarations'], isEmpty);
      expect(decoded['transformCounts'], {'constructorShorthand': 3});
      expect(decoded['skipReasonCounts'], isEmpty);
      expect(await formattedFile(root, 'lib/add_investment_choice.dart'), '''
class AddInvestmentChoice {
  const new _({this.apiSymbol});

  const new custom() : this._();

  const new apiBacked(SupportedApiSymbol symbol) : this._(apiSymbol: symbol);

  final SupportedApiSymbol? apiSymbol;

  bool get isApiBacked => apiSymbol != null;
  bool get isCustom => apiSymbol == null;
}
''');
    });

    test('rewrites syntax-valid constructor shorthand candidates', () async {
      final root = await createPackageRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      const originalSource = '''
class ShorthandSafety {
  ShorthandSafety.eligible();

  factory ShorthandSafety.factoryConstructor() => ShorthandSafety.eligible();

  external ShorthandSafety.externalConstructor();

  @deprecated
  ShorthandSafety.metadataConstructor();

  /// Constructor comment.
  ShorthandSafety.commentedConstructor();

  ShorthandSafety.parameterMetadata(@deprecated String value);
}
''';
      writeFile(root, 'lib/shorthand_safety.dart', originalSource);

      final result = await runCli([
        'primary-constructors',
        root.path,
        '--json',
      ]);

      expect(result.exitCode, exitSuccess);
      expect(result.stderr, isEmpty);
      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(decoded['changedFiles'], ['lib/shorthand_safety.dart']);
      expect(decoded['migratedDeclarations'], [
        {
          'path': 'lib/shorthand_safety.dart',
          'declarationKind': 'constructor',
          'declarationName': 'ShorthandSafety.eligible',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf('ShorthandSafety.eligible'),
        },
        {
          'path': 'lib/shorthand_safety.dart',
          'declarationKind': 'constructor',
          'declarationName': 'ShorthandSafety.externalConstructor',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf(
            'external ShorthandSafety.externalConstructor',
          ),
        },
        {
          'path': 'lib/shorthand_safety.dart',
          'declarationKind': 'constructor',
          'declarationName': 'ShorthandSafety.metadataConstructor',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf('@deprecated'),
        },
        {
          'path': 'lib/shorthand_safety.dart',
          'declarationKind': 'constructor',
          'declarationName': 'ShorthandSafety.commentedConstructor',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf('/// Constructor comment.'),
        },
        {
          'path': 'lib/shorthand_safety.dart',
          'declarationKind': 'constructor',
          'declarationName': 'ShorthandSafety.parameterMetadata',
          'transform': 'constructorShorthand',
          'offset': originalSource.indexOf('ShorthandSafety.parameterMetadata'),
        },
      ]);
      expect(decoded['skippedDeclarations'], isEmpty);
      expect(decoded['transformCounts'], {'constructorShorthand': 5});
      expect(decoded['skipReasonCounts'], isEmpty);
      expect(await formattedFile(root, 'lib/shorthand_safety.dart'), '''
class ShorthandSafety {
  new eligible();

  factory ShorthandSafety.factoryConstructor() => ShorthandSafety.eligible();

  external new externalConstructor();

  @deprecated
  new metadataConstructor();

  /// Constructor comment.
  new commentedConstructor();

  new parameterMetadata(@deprecated String value);
}
''');
    });

    test(
      'keeps factory constructors and rewrites documented external shorthand',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        const originalSource = '''
class ConstructorShorthandRegression {
  const ConstructorShorthandRegression.named();

  /// External hook.
  external ConstructorShorthandRegression.hook();

  factory ConstructorShorthandRegression.factoryConstructor() => ConstructorShorthandRegression.named();
}
''';
        writeFile(
          root,
          'lib/constructor_shorthand_regression.dart',
          originalSource,
        );

        final result = await runCli([
          'primary-constructors',
          root.path,
          '--json',
        ]);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['changedFiles'], [
          'lib/constructor_shorthand_regression.dart',
        ]);
        expect(decoded['migratedDeclarations'], [
          {
            'path': 'lib/constructor_shorthand_regression.dart',
            'declarationKind': 'constructor',
            'declarationName': 'ConstructorShorthandRegression.named',
            'transform': 'constructorShorthand',
            'offset': originalSource.indexOf(
              'const ConstructorShorthandRegression.named',
            ),
          },
          {
            'path': 'lib/constructor_shorthand_regression.dart',
            'declarationKind': 'constructor',
            'declarationName': 'ConstructorShorthandRegression.hook',
            'transform': 'constructorShorthand',
            'offset': originalSource.indexOf('/// External hook.'),
          },
        ]);
        expect(decoded['skippedDeclarations'], isEmpty);
        expect(decoded['transformCounts'], {'constructorShorthand': 2});
        expect(
          await formattedFile(
            root,
            'lib/constructor_shorthand_regression.dart',
          ),
          '''
class ConstructorShorthandRegression {
  const new named();

  /// External hook.
  external new hook();

  factory ConstructorShorthandRegression.factoryConstructor() =>
      ConstructorShorthandRegression.named();
}
''',
        );
      },
    );

    for (final scenario in [
      (
        name: 'external unnamed constructor',
        relativePath: 'lib/external_constructor.dart',
        declarationName: 'ExternalConstructor',
        reason: 'externalConstructor',
        message: 'External constructors are not supported.',
        offsetNeedle: 'external ExternalConstructor',
        source: '''
class ExternalConstructor {
  external ExternalConstructor();
}
''',
        expectedFormatted: '''
class ExternalConstructor {
  external new();
}
''',
      ),
      (
        name: 'constructor metadata',
        relativePath: 'lib/constructor_metadata.dart',
        declarationName: 'ConstructorMetadata',
        reason: 'constructorMetadata',
        message: 'Constructor metadata is not moved to primary constructors.',
        offsetNeedle: '@deprecated',
        source: '''
class ConstructorMetadata {
  final String id;

  @deprecated
  ConstructorMetadata(this.id);
}
''',
        expectedFormatted: '''
class ConstructorMetadata {
  final String id;

  @deprecated
  new(this.id);
}
''',
      ),
      (
        name: 'constructor documentation comment',
        relativePath: 'lib/constructor_documentation_comment.dart',
        declarationName: 'ConstructorDocumentationComment',
        reason: 'constructorComment',
        message: 'Constructor comments are not moved to primary constructors.',
        offsetNeedle: '/// Constructor comment.',
        source: '''
class ConstructorDocumentationComment {
  final String id;

  /// Constructor comment.
  ConstructorDocumentationComment(this.id);
}
''',
        expectedFormatted: '''
class ConstructorDocumentationComment {
  final String id;

  /// Constructor comment.
  new(this.id);
}
''',
      ),
    ]) {
      test(
        'keeps primary skip and rewrites retained ${scenario.name}',
        () async {
          final root = await createPackageRoot();
          addTearDown(() => root.deleteSync(recursive: true));
          writeFile(root, scenario.relativePath, scenario.source);

          final result = await runCli([
            'primary-constructors',
            root.path,
            '--json',
          ]);

          expect(result.exitCode, exitSuccess);
          expect(result.stderr, isEmpty);
          final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
          expect(decoded['changedFiles'], [scenario.relativePath]);
          expect(decoded['migratedDeclarations'], [
            {
              'path': scenario.relativePath,
              'declarationKind': 'constructor',
              'declarationName': scenario.declarationName,
              'transform': 'constructorShorthand',
              'offset': scenario.source.indexOf(scenario.offsetNeedle),
            },
          ]);
          expect(decoded['skippedDeclarations'], [
            {
              'path': scenario.relativePath,
              'declarationKind': 'class',
              'declarationName': scenario.declarationName,
              'transform': 'primaryConstructor',
              'offset': 0,
              'reason': scenario.reason,
              'message': scenario.message,
            },
          ]);
          expect(decoded['transformCounts'], {'constructorShorthand': 1});
          expect(decoded['skipReasonCounts'], {scenario.reason: 1});
          expect(
            await formattedFile(root, scenario.relativePath),
            scenario.expectedFormatted,
          );
        },
      );
    }

    test(
      'rewrites constructors in a class skipped for an additional named constructor',
      () async {
        final root = await createPackageRoot();
        addTearDown(() => root.deleteSync(recursive: true));
        const originalSource = '''
class AppDatabase extends _\$AppDatabase {
  AppDatabase() : super(impl.connect());

  AppDatabase.forTesting(super.e);
}
''';
        writeFile(root, 'lib/app_database.dart', originalSource);

        final result = await runCli([
          'primary-constructors',
          root.path,
          '--json',
        ]);

        expect(result.exitCode, exitSuccess);
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
        expect(decoded['changedFiles'], ['lib/app_database.dart']);
        expect(decoded['migratedDeclarations'], [
          {
            'path': 'lib/app_database.dart',
            'declarationKind': 'constructor',
            'declarationName': 'AppDatabase',
            'transform': 'constructorShorthand',
            'offset': originalSource.indexOf('AppDatabase()'),
          },
          {
            'path': 'lib/app_database.dart',
            'declarationKind': 'constructor',
            'declarationName': 'AppDatabase.forTesting',
            'transform': 'constructorShorthand',
            'offset': originalSource.indexOf('AppDatabase.forTesting'),
          },
        ]);
        expect(decoded['skippedDeclarations'], [
          {
            'path': 'lib/app_database.dart',
            'declarationKind': 'class',
            'declarationName': 'AppDatabase',
            'transform': 'primaryConstructor',
            'offset': 0,
            'reason': 'namedConstructor',
            'message': 'Named generative constructors are not supported.',
          },
        ]);
        expect(decoded['transformCounts'], {'constructorShorthand': 2});
        expect(decoded['skipReasonCounts'], {'namedConstructor': 1});
        expect(await formattedFile(root, 'lib/app_database.dart'), '''
class AppDatabase extends _\$AppDatabase {
  new() : super(impl.connect());

  new forTesting(super.e);
}
''');
      },
    );

    for (final scenario in [
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
        name: 'unsupported constructor body',
        declarationName: 'UnsupportedBodyConstructor',
        reason: 'unsupportedConstructorBody',
        message: 'This constructor body shape is not supported.',
        source: '''
class UnsupportedBodyConstructor {
  final String id;

  const UnsupportedBodyConstructor(this.id) {
    print(id);
  }
}
''',
      ),
    ]) {
      test('skips unsafe ${scenario.name} shape precisely', () async {
        await expectSinglePrimaryConstructorSkip(
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
        await expectSinglePrimaryConstructorSkip(
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
      (
        name: 'multi-variable field with shared comments',
        declarationName: 'MultiVariableCommentedField',
        reason: 'fieldComment',
        message:
            'Ambiguous field comments are not moved to declaring parameters.',
        source: '''
class MultiVariableCommentedField {
  /// Shared identity fields.
  final String id, name;

  MultiVariableCommentedField(this.id, this.name);
}
''',
      ),
    ]) {
      test('skips ${scenario.name} precisely', () async {
        await expectSinglePrimaryConstructorSkip(
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

      await expectSinglePrimaryConstructorSkip(
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

  UnsupportedInitializer(this.id) : id = id;
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/initializer.dart',
        originalSource: originalSource,
        declarationName: 'UnsupportedInitializer',
        reason: 'unsupportedInitializer',
        message: 'This constructor initializer is not supported.',
      );
    });

    test('skips unused private-field initializers precisely', () async {
      const originalSource = '''
class UnusedPrivateInitializer {
  final String id;
  final String _id;

  UnusedPrivateInitializer(this.id) : _id = id;
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/unused_private_initializer.dart',
        originalSource: originalSource,
        declarationName: 'UnusedPrivateInitializer',
        reason: 'unsupportedInitializer',
        message: 'This constructor initializer is not supported.',
      );
    });

    test('skips initializer dependencies on instance state precisely', () async {
      const originalSource = '''
class UnsafeInitializerDependency {
  final int base;
  final int total;

  UnsafeInitializerDependency(this.base) : total = this.base + 1;
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/initializer_dependency.dart',
        originalSource: originalSource,
        declarationName: 'UnsafeInitializerDependency',
        reason: 'unsafeInitializerDependency',
        message:
            'Initializer field assignments must depend only on constructor parameters.',
      );
    });

    test('skips constructor-call initializer non-parameter arguments', () async {
      const originalSource = '''
class UnsafeInitializerDependency {
  final WidgetTester tester;
  final NavigationRobot navigation;

  UnsafeInitializerDependency(this.tester)
      : navigation = NavigationRobot(sharedTester);
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/initializer_dependency.dart',
        originalSource: originalSource,
        declarationName: 'UnsafeInitializerDependency',
        reason: 'unsafeInitializerDependency',
        message:
            'Initializer field assignments must depend only on constructor parameters.',
      );
    });

    test('skips moved initializers before existing field initializers', () async {
      const originalSource = '''
class OrderedInitializers {
  OrderedInitializers(this.tester) : navigation = NavigationRobot(tester);

  final WidgetTester tester;
  final NavigationRobot navigation;
  final SettingsRobot settings = SettingsRobot();
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/initializer_order.dart',
        originalSource: originalSource,
        declarationName: 'OrderedInitializers',
        reason: 'unsafeInitializerOrder',
        message:
            'Moving initializer field assignments would change initializer evaluation order.',
      );
    });

    test('skips moved initializer fields in changed relative order', () async {
      const originalSource = '''
class ReorderedInitializers {
  ReorderedInitializers(this.tester)
      : settings = SettingsRobot(tester),
        navigation = NavigationRobot(tester);

  final WidgetTester tester;
  final NavigationRobot navigation;
  final SettingsRobot settings;
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/reordered_initializers.dart',
        originalSource: originalSource,
        declarationName: 'ReorderedInitializers',
        reason: 'unsafeInitializerOrder',
        message:
            'Moving initializer field assignments would change initializer evaluation order.',
      );
    });

    test('skips moved initializers after retained assertions', () async {
      const originalSource = '''
class RetainedBeforeMoved {
  final int value;
  final int doubled;

  RetainedBeforeMoved(this.value)
      : assert(value > 0),
        doubled = value * 2;
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/retained_before_moved.dart',
        originalSource: originalSource,
        declarationName: 'RetainedBeforeMoved',
        reason: 'unsafeInitializerOrder',
        message:
            'Moving initializer field assignments would change initializer evaluation order.',
      );
    });

    test('skips moved initializers after retained super calls', () async {
      const originalSource = '''
class RetainedSuperBeforeMoved extends Base {
  final int value;
  final int doubled;

  RetainedSuperBeforeMoved(this.value)
      : super(value),
        doubled = value * 2;
}

class Base(final Object value);
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/super_before_moved.dart',
        originalSource: originalSource,
        declarationName: 'RetainedSuperBeforeMoved',
        reason: 'unsafeInitializerOrder',
        message:
            'Moving initializer field assignments would change initializer evaluation order.',
      );
    });

    test('skips assignment-in-body field initialization precisely', () async {
      const originalSource = '''
class FieldInitializingBody {
  String? id;

  FieldInitializingBody(String id) {
    this.id = id;
  }
}
''';

      await expectSinglePrimaryConstructorSkip(
        relativePath: 'lib/body_field_initializer.dart',
        originalSource: originalSource,
        declarationName: 'FieldInitializingBody',
        reason: 'fieldInitializingConstructorBody',
        message:
            'Constructor bodies that initialize instance fields are not supported.',
      );
    });

    for (final scenario in [
      (
        name: 'final field writes',
        declarationName: 'FinalFieldWriteBody',
        source: '''
class FinalFieldWriteBody {
  final int count;

  FinalFieldWriteBody(this.count) {
    count++;
  }
}
''',
      ),
      (
        name: 'unmapped field writes',
        declarationName: 'UnmappedFieldWriteBody',
        source: '''
class UnmappedFieldWriteBody {
  int count;

  UnmappedFieldWriteBody(int start) {
    count = start;
  }
}
''',
      ),
      (
        name: 'unresolved write targets',
        declarationName: 'UnresolvedWriteTargetBody',
        source: '''
class UnresolvedWriteTargetBody {
  int count;

  UnresolvedWriteTargetBody(this.count, dynamic target) {
    target.count = count;
  }
}
''',
      ),
    ]) {
      test('skips ${scenario.name} in constructor bodies precisely', () async {
        await expectSinglePrimaryConstructorSkip(
          relativePath: 'lib/body_field_write.dart',
          originalSource: scenario.source,
          declarationName: scenario.declarationName,
          reason: 'fieldInitializingConstructorBody',
          message:
              'Constructor bodies that initialize instance fields are not supported.',
        );
      });
    }
  });
}
